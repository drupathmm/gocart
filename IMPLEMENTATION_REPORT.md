# GoCart server-side checkout implementation report

**Prepared:** 13 October 2026
**Scope:** Current GoCart workspace changes and steps needed to connect and verify a Supabase project.

## Summary

> **Current release gate (2026-10-27):** this report describes local
> implementation contracts, not a deployable database release. The verified
> GoCart database has a legacy order schema and an empty recorded migration
> history despite existing data. The local migration chain has not been
> validated against an owner-approved restored copy of that schema. Do not run
> `supabase db push`, replay the migration chain, or treat a successful Pages
> build as evidence that the backend is compatible. The SQL migrations and
> drafts in this repository are review material until that reconciliation and
> database testing are complete.

Checkout order creation is routed through the authenticated `checkout` Edge Function and the PostgreSQL `place_order` function. Product prices, stock decrement, coupon validation/usage, order totals, and cart clearing are decided within the database transaction. Direct client writes to orders and order items are revoked. Product stock changes, including the initial quantity when creating a product, use a server-side function.

The Flutter client and Edge Function code are present in this workspace. I did **not** connect to or change a hosted Supabase project, apply the migration remotely, deploy the Edge Functions, or run the database acceptance checks. Connection state is therefore unverified.

## Changes in the workspace

### Database migration

File: `supabase/migrations/20261008000000_server_side_checkout.sql`

- Evolves the existing `orders` schema to use `user_id` and `total_amount`, adds an idempotency key and Razorpay order reference, and constrains order status and non-negative totals.
- Adds `offers` and `offer_redemptions`, including offer limits, date range, discount details, and unique redemption per order.
- Gives `order_items` a UUID primary key. The previous identity key is retained under `legacy_id`.
- Enables RLS on orders, order items, cart items, products, and offers. Order and order-item reads are scoped to the signed-in buyer; cart reads are scoped to the signed-in owner.
- Revokes authenticated/anonymous table writes to orders and order items. Product updates exclude `stock`; product inserts exclude `stock` as well.
- Adds `merchant_set_product_stock`, `place_order`, `change_order_status`, and an owner-only cancellation wrapper.
- `place_order` authenticates the caller, locks per-user checkout and idempotency keys, snapshots cart rows, locks products and cart rows in a stable order, atomically decrements stock, records server prices, validates and consumes an offer, stores the final total, and removes only the cart rows in its checkout snapshot.
- `change_order_status` enforces the requested transitions. Cancellation restores product stock and coupon usage in the same transaction.

### Edge Functions

- `supabase/functions/checkout/index.ts`: validates the JSON request, verifies the caller with `auth.getUser()`, invokes `place_order`, maps checkout errors to HTTP responses, and returns the server total.
- `supabase/functions/create-razorpay-order/index.ts`: creates a Razorpay order from the saved database total and stores its Razorpay ID on the order from the server.
- `supabase/functions/verify-payment/index.ts`: checks the Razorpay HMAC signature, confirms the associated order belongs to the authenticated user, and marks the order paid using the server-side status function.
- `supabase/config.toml` requires JWT verification for these functions.

### Flutter app

- `lib/services/order_service.dart` invokes the `checkout` Edge Function instead of creating an order through a direct table write. It maps server error codes into checkout exceptions.
- `lib/models/checkout_exception.dart` provides buyer-facing messages for stock, cart, offer, and authentication errors.
- `lib/screens/checkout_screen.dart` submits a stable idempotency key, carries the optional offer code, prevents duplicate submissions while a request is active, and shows loading/error/empty/content states.
- `lib/services/product_service.dart` omits stock from product inserts and sends initial and changed stock through `merchant_set_product_stock`.
- `lib/screens/user_home_screen.dart` debounces product search by 300 ms.
- `lib/config/env.dart`, `.env.example`, `.gitignore`, `lib/main.dart`, and `.github/workflows/deploy.yml` configure Supabase URL/key injection without committing `.env` values.

### Existing schema compatibility

This repository’s `products.id` is `bigint`, and the current app models and cart use that type. Therefore `order_items.product_id` remains `bigint` to reference the existing catalog. Converting product IDs to UUID would require a separate coordinated migration of products, cart rows, app models, queries, and stored references; that conversion was not made here.

## Current payment integration limitation

The server-side Razorpay Edge Functions and Flutter's Android/iOS test-mode Checkout path are now wired: Flutter requests an order using the saved GoCart order, launches the native SDK with server-returned values, and submits callback fields to server verification. The Edge Function refuses non-test key identifiers. The demo/no-charge path remains available. Automated tests validate response boundaries, but the native SDK and provider exchange have not been exercised with Razorpay credentials. Never put the Razorpay secret or Supabase service-role/secret key in Flutter.

## Configuration and Supabase connection

### Check local Flutter configuration

There is an ignored `.env` file in the workspace, but I did not read its values or test a live connection. The committed template `.env.example` contains empty placeholders. Check locally that `.env` contains the Supabase **Project URL** and the project’s **anon/publishable client key**:

```dotenv
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<anon-or-publishable-client-key>
```

Keep `.env` private; it is ignored by Git. Start the app with:

```sh
flutter run --dart-define-from-file=.env
```

The browser/mobile client key is intended to be used with RLS. Do not put a `service_role` or Supabase secret key in this file.

### Hosted Supabase deployment status

Do not use the historical deployment commands or apply the migration chain to
the hosted GoCart project. Its legacy orders contain demo payment states,
`order_items.id` is bigint with existing foreign-key dependencies, and the
recorded migration history is empty. The local `20261008000000` checkout
migration has incompatible transformations and must not be replayed to bypass
its preflight. First obtain an owner-approved backup and verified isolated
restore, reconcile a forward-only migration against that baseline, and pass
SQL integration tests there. Only then can the owner approve an exact
production migration and Edge Function rollout. No such deployment is
approved by this report.

For production Razorpay payments, configure `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` as **Supabase Edge Function secrets**, using the Supabase Dashboard’s Edge Function Secrets page or the CLI. Do not commit them. The functions also read Supabase URL/API key environment values supplied by the Supabase runtime; this code currently uses the legacy `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` environment names for those clients. Supabase currently documents legacy variables alongside newer publishable/secret key variables; if the target project/runtime does not expose the legacy names, update the Edge Function client initialization to the key variables available in that project before deploying.

If the app is built by the included GitHub Pages workflow, add repository Actions secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY` under the repository’s Settings → Secrets and variables → Actions.

The Supabase CLI’s current migration workflow requires linking the project before `db push`; see [Supabase CLI reference](https://supabase.com/docs/reference/cli/v0/supabase-secrets) and [Edge Function secrets documentation](https://supabase.com/docs/guides/functions/secrets).

## Verification already completed

- `dart format lib test`: completed; 41 files checked, 0 changed.
- `flutter analyze --no-pub`: passed with **No issues found**.
- `flutter test --no-pub`: most recent local run passed all **10 tests** after
  the persistent checkout and pending-merchant UI changes.
- `flutter analyze --no-pub`: most recent local run passed with no issues.
- `git diff --check`: no whitespace errors (Git emitted only line-ending conversion notices for existing changed Dart files).
- Searched the app and Supabase function/migration files for direct order inserts and literal Razorpay/Supabase secret values. The client uses the checkout function and no literal secret values were found. The ignored `.env` contents were not inspected.

## Verification still needed against Supabase

These checks require a linked staging Supabase project with the migration applied. They were **not run** in this workspace.

1. **Migration application:** first review and test all migrations on a disposable local Supabase stack. Do not run `supabase link`, `supabase db push`, or use the hosted SQL Editor for this repository until the developer confirms an isolated development project and explicitly approves a remote operation. The screenshot in this task showed the hosted project marked **PRODUCTION**.
2. **Concurrent stock:** arrange a product with stock `1` and two authenticated users with that product in their carts. Submit checkout requests concurrently. Verify one order succeeds, the other receives `OUT_OF_STOCK`, stock ends at `0`, and no partial order/line/coupon/cart mutation is left from the failure. `scripts/concurrency_check.sql` documents the intended concurrency check but is not an automated concurrent runner.
3. **Direct REST write denial:** with an authenticated user JWT, attempt `POST /rest/v1/orders` and `POST /rest/v1/order_items`. Both must be rejected; confirm the response and database grants/RLS. Also try changing `products.stock` directly and confirm rejection.
4. **Price integrity:** change the displayed/client-held product price without changing the database, then check out. Verify order item `unit_price` and `orders.total_amount` match the database price at checkout.
5. **Coupon limits and rollback:** test invalid, expired, minimum-order, global usage-limit, and per-user-limit cases; retry a failed checkout and confirm stock/usage/cart state rolled back.
6. **Payment:** with Razorpay test credentials configured as Edge Function secrets, test order creation and valid/invalid signatures. Confirm only a valid payment advances an owned pending order to `paid`, and invalid status transitions are rejected.
7. **Deployed client:** run/build Flutter with the intended project URL and public client key, sign in, and verify cart, checkout, order history, RLS, and useful retry/error messages against the deployed functions.

## Files to review

- `supabase/migrations/20261008000000_server_side_checkout.sql`
- `supabase/functions/checkout/index.ts`
- `supabase/functions/create-razorpay-order/index.ts`
- `supabase/functions/verify-payment/index.ts`
- `lib/services/order_service.dart`
- `lib/services/product_service.dart`
- `lib/screens/checkout_screen.dart`
- `lib/config/env.dart`
- `.env.example`
- `README.md`
