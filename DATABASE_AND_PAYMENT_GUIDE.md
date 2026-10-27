# GoCart Database and Payment Guide

Updated: 2026-10-14

This guide describes the repository implementation and its remaining work.
The historical local-stack test results below refer to an earlier local
schema; they do not validate the current migration set against the verified
legacy GoCart database. The migration chain has not been validated against an
owner-approved restored copy of that database and has not been applied to a
hosted database. Treat current SQL migrations and drafts as review material,
not an approved deployment package. Do not replay the chain or use
`supabase db push` to bypass the schema/history mismatch.

## What the database does

Think of PostgreSQL as GoCart's shared source of truth. Flutter displays and
collects information; database rules decide which rows a signed-in person can
read or change. Supabase Auth owns login identities. `profiles.id` points to
the matching Auth user.

| Table | Purpose | Important links and protection |
| --- | --- | --- |
| `profiles` | Name, email, user/merchant/admin role, merchant approval state | ID is the Auth user ID. Signed-in users read their own profile; admins can list profiles. New merchants start `pending`. |
| `products` | Product catalogue and stock | `id` is bigint to match the current Dart model. Each row belongs to a merchant profile. Stock is changed through a database function. |
| `cart_items` | Persistent buyer cart | Belongs to a profile and product. A unique `(user_id, product_id)` prevents duplicate rows. Quantity is bounded. |
| Supabase Storage `product-images` bucket | Public product photos | The base migration configures the bucket and permits approved merchants to upload within their own user-ID folder. |
| `orders` | A checkout attempt and its database-calculated total | Created by the checkout SQL function, not by a direct Flutter insert. |
| `order_items` | Purchase-time copy of product name, price, quantity, merchant and line total | Belongs to one order; keeps order contents readable if the product changes later. |
| `offers` | Coupon definitions and limits | Checkout validates dates, minimums, limits and discount on the server. |
| `offer_redemptions` | Coupon use tied to the buyer and order | Supports per-user limits and safe cancellation accounting. |
| `order_status_history` | Append-only record of status changes | Database triggers record status, time and the verified actor. |

The first three tables are the missing foundation: current migrations already
alter them and current Flutter code queries them, but no checked-in earlier
migration creates them. Orders/offers arrive in the existing later checkout
migration. Status history is a separate later migration.

## Database files and dependencies

The migration order is important. A fresh database needs these objects before
the existing migrations can run:

1. `20260926000000_gocart_base_schema.sql` (new draft) creates `profiles`,
   `products`, `cart_items`, their indexes and RLS policies, the initial
   cart/profile functions, and the `product-images` Storage bucket/policies.
2. `20260927000000_harden_profile_and_cart_writes.sql` assumes those tables and
   these exact functions exist: `add_to_cart(bigint, integer)`,
   `update_cart_quantity(bigint, integer)`, and
   `approve_my_merchant_account()`.
3. `20260927010000_demo_orders_checkout.sql` creates the initial `orders` and
   `order_items` structure and demo checkout function.
4. `20261008000000_server_side_checkout.sql` evolves orders and adds offers,
   redemption tracking, checkout, cancellation and status functions. It
   preserves `products.id` as bigint.
5. `20261013000000_enforce_merchant_product_authorization.sql` tightens product
   writes and defines `merchant_set_product_stock(bigint, integer)`.
6. `20261013010000_require_checkout_idempotency.sql` exposes the required-key
   checkout wrapper used by the Edge Function.
7. `20261013020000_add_order_status_history.sql` adds immutable status history.

The database foundation also depends on Supabase Auth's `auth.users`, the
standard `anon`, `authenticated`, and `service_role` database roles, and the
`auth.uid()` / `auth.role()` helpers. These are supplied by Supabase, not by
GoCart SQL. The current migration set does not create these Supabase internals.

## Review findings and fixes in this revision

- The earlier profile read policy looked up admin status by querying
  `profiles` inside a policy on `profiles`. That can recursively invoke the
  same policy. The draft now calls `is_current_user_admin()`, a narrow
  `SECURITY DEFINER` helper that returns only a true/false result for the
  caller's identity. Its search path is empty and only signed-in users can run
  it. This still needs a local two-user/admin RLS test.
- The product policy name and cart read policy name now match the later
  migration's `DROP POLICY` statements, avoiding a duplicate-policy creation
  error when a fresh database runs migrations in timestamp order.
- Database checks now restrict categories to the Flutter category list and
  require the old compatibility column `price` to equal `offer_price`. The
  current `ProductService` writes both fields together. This prevents a stale
  legacy value from disagreeing with the price shown by current screens.
- The profile insert trigger copies email from Supabase Auth and assigns
  merchant status itself. Normal accounts cannot set their own role or
  approval status through the granted columns. Admin reads are separated from
  regular users' own-profile reads.
- `ProductService` also requires the `product-images` Storage bucket. The base
  draft now configures it as public because the app renders public image URLs,
  limits files to 5 MiB JPEG/PNG/WebP, and allows approved merchants to upload
  only beneath their own user-ID folder. Merchant cleanup is restricted to its
  own folder; admins can remove product images. Storage behavior needs local
  verification.
- A trusted local seed still needs to provision the first admin profile after
  its Auth user exists. This is a development setup step and must never be
  exposed as a public signup option.

The database draft is not confirmed correct until the ordered migrations apply
on an empty local Supabase stack and the pgTAP tests pass. In particular,
verify the Supabase-provided `extensions` schema/`pgcrypto` setup and the
admin helper's behavior with the actual local Supabase database owner.

### SQL functions in everyday language

- `add_to_cart` and `update_cart_quantity` verify the signed-in user, lock the
  product row, check stock and quantity, and update the correct user's cart.
- `place_order` locks the buyer's checkout and product rows, reads the real
  database price, decrements stock, snapshots order lines, validates a coupon,
  clears only the cart rows included in that attempt, and returns the order ID.
  PostgreSQL treats it as one transaction: if a step fails, its earlier writes
  roll back too.
- `checkout_place_order` requires a stable retry key and calls `place_order`.
- `change_order_status` is a restricted server-side function; clients cannot
  directly set the order's status. `cancel_own_order` checks the buyer before
  calling it.
- `merchant_set_product_stock` checks merchant ownership and approval before
  changing stock. Its existing contract sets an absolute stock count; changing
  that behavior needs a caller review and approval.
- `admin_set_merchant_status` allows the admin path to approve or suspend a
  merchant. Ordinary profile updates cannot change role or approval status.

`SECURITY DEFINER` means a function runs with its owner's database rights. It
is useful where RLS intentionally blocks direct writes, but it is powerful.
These functions therefore need a fixed/empty search path, must derive the user
from `auth.uid()`, check ownership/role inside the function, and have execute
grants limited to the intended caller.

## Flutter and Edge Function mapping

- `ProductService` reads and writes `products`; product writes check the
  merchant in the service, while database RLS/function checks are the real
  security boundary. It calls `merchant_set_product_stock` for stock.
- `CartService` reads the signed-in user's `cart_items` joined to `products`,
  and calls the cart functions for quantity changes.
- `ProfileService` reads and updates the current profile.
- `OrderService` invokes the `checkout` Edge Function and reads the signed-in
  buyer's orders.
- `checkout` authenticates the request with Supabase Auth and calls
  `checkout_place_order`; it returns a friendly stable error code.
- `create-razorpay-order` reads the pending GoCart order and asks Razorpay to
  create a matching INR amount in paise.
- `verify-payment` checks the Razorpay checkout HMAC, checks authenticated
  ownership, and requests a `pending -> paid` transition.

## Payment flow and remaining security work

The intended sequence is: database creates a pending order and total; server
creates the Razorpay order for that exact amount; Flutter launches Razorpay
Checkout; Flutter sends the returned IDs/signature to `verify-payment`; only
after server verification does GoCart show the order as paid.

The local server/database safety stage is implemented, but the repository is
not yet end-to-end payment ready:

1. The current Flutter checkout creates an unpaid GoCart order and offers a
   separate Android/iOS Razorpay test-mode flow; it does not report a demo
   payment as provider-confirmed. Historical `demo_paid` records remain demo
   history and are not evidence of Razorpay capture. The test-mode key is
   validated by Flutter; local order
   creation, verification, webhook and reconciliation entrypoints now fail
   closed unless configured with an `rzp_test_` key ID. Provider integration
   has not been exercised with Razorpay credentials or provider traffic.
2. `verify-payment` now checks the HMAC, authenticated buyer/order mapping, and
   independently fetches the payment from Razorpay. It requires captured state,
   matching payment/provider order IDs, INR, and the saved amount in paise. This
   code has not been exercised against Razorpay credentials.
3. Local `razorpay_payment_attempts`, `razorpay_refunds`, and
   `razorpay_webhook_events` tables record expected amounts, unique provider
   IDs, and distinct processing states. Service-only database functions guard
   claims, verified payment transitions, refund records, and webhook event IDs.
   The payment-attempt ledger grants `service_role` read-only access for
   verification; `anon` and `authenticated` have no ledger access.
4. `razorpay-webhook` and its shared handler are implemented. They verify the
   exact raw body with a dedicated webhook secret, claim events with a fenced
   lease, quarantine malformed/conflicting signed deliveries, fetch provider
   payment state before applying the verified-payment RPC, and return retryable
   errors when durable processing fails. The local Edge Runtime and mocked
   handler tests were validated with synthetic data. Live provider behavior,
   scheduled reconciliation, and an operator quarantine workflow are not
   established as production-ready.
5. `create-razorpay-order` now claims one attempt per GoCart order without
   holding a database transaction across the provider call. Ambiguous outcomes
   search Razorpay orders by the deterministic receipt before continuing. If
   no order can be confirmed, it blocks recreation for reconciliation. This
   reduces duplicates but does not guarantee exactly-once provider execution.
6. Refund request/result states are recorded separately from order
   cancellation. There is no live refund API caller; a payment is shown as
   refunded only after a trusted provider result is recorded.
   Cancellation currently restores stock and offer usage immediately. The
   cancellation window, restoration timing, full/partial refund rules, retry
   handling, and late capture after cancellation require business approval.
7. Payment functions require Supabase and Razorpay secrets at runtime. The repository does
   not contain those credentials, and they must never be placed in Flutter or
   committed files. Only a Razorpay public key ID may go to the client.
8. Flutter checkout is wired locally to the server order-creation and
   verification functions and has a native Razorpay Checkout screen. The Edge
   Functions and migrations are not deployed, and no Razorpay device/provider
   payment has been run in this workspace.

### Safe payment implementation sequence

1. Local tests now cover signature validation, owner/order and amount/currency
   mismatches, duplicate verification/claims, and refund state consistency.
2. Local schema now claims one provider order per GoCart order, fences concurrent
   calls, and leaves ambiguous results for receipt-based reconciliation.
3. Local verification now requires Razorpay's authenticated payment fetch and
   captured, matching provider facts before the database can mark an order paid.
4. Wire Flutter to the existing server order creation and verification
   functions using Razorpay Checkout in test mode. Handle success, failure,
   cancellation, timeouts, duplicate callbacks and app-restart recovery.
5. Configure a separate Firebase project and implement the required FCM token
   lifecycle, server sender, order events and app lifecycle handling.
6. Run local unit/database tests. Provider test-mode checks require separate
   developer configuration and explicit review; never use production for these
   checks.

### Razorpay Android test-mode checklist

The following is a future test checklist; no device/emulator or provider test
was performed in this review.

- Use test-mode credentials only. Configure the existing server secret names
  `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and
  `RAZORPAY_WEBHOOK_SECRET` only in the approved test Edge Function
  environment. Supply the public test `RAZORPAY_KEY_ID` to Flutter through
  the existing app configuration. Never put the key secret or webhook secret
  in Flutter, `.env` files, source control, screenshots, or logs.
- Confirm Flutter launches Checkout with a server-created order and server
  calculated amount, then exercise success return, app background/relaunch,
  timeout and duplicate callback handling. A client callback must never mark
  an order paid by itself.
- Verify checkout signature handling and server-side provider lookup enforce
  the expected payment/order IDs, captured state, amount and INR before the
  capture RPC can change order state.
- For webhook testing, an owner-approved test deployment must configure the
  webhook endpoint and matching test secret in the Razorpay test dashboard.
  Send signed test events and verify raw-request-body signature checking,
  durable event claims, duplicate delivery idempotency, and conflict/review
  behavior.
- Exercise failed, cancelled, timed-out, authorized-only and interrupted
  payments, then compare order, attempt, reservation/stock and notification
  states. Verify recovery does not falsely mark paid or release stock when
  provider outcome is uncertain.
- Do not perform real payments or refunds. No deployment or provider API call
  is authorized by this checklist.

## In-app notification status

The existing `admin_merchant_notifications` inbox covers pending merchant
registrations. The new local migration
`20261027130000_user_event_notifications.sql` adds recipient-scoped events for
admin status decisions and reinstatement requests, merchant status/review
outcomes, order creation/status changes, and verified captured payments. Order
and status notifications are created in the same database transaction as the
source event. Payment notifications are emitted after the payment-attempt row
becomes `captured` and the matching order is already paid, avoiding a race with
the current capture RPC's update order. The Flutter inbox uses RLS-scoped reads
and an authenticated mark-read RPC. The migration and inbox are local only;
they have not been applied or database-tested.

## Important approval and compatibility notes

- Merchant signup previously called `approve_my_merchant_account()` after a
  five-second wait. The signup screen now makes no approval RPC call and shows
  a pending-admin-review message. Login and app startup also prevent pending
  merchants from entering the merchant dashboard. The database remains the
  real boundary through `merchant_status` and product policies/functions.
  The current app has no caller for the obsolete RPC. The local migration
  `20261025140412_harden_merchant_approval_and_truncate.sql` removes it and
  reasserts that new merchant profiles always start pending; it is not proof
  that the hosted GoCart database has that migration.
- The app's existing `merchant_set_product_stock` accepts a desired stock
  value. Concurrent order decrements can race with an absolute stock set. A
  delta adjustment API is safer, but changing the contract requires checking
  all callers and is a separate phase.
- The current SQL status graph includes shipped, delivered, return requested
  and cancellation transitions, but merchant authorization for shipping,
  delivery actor, return rules and paid cancellation/refund policy remain
  undecided. The guide's merchant fulfillment workflow is not complete. Do not
  widen those transitions until a lead approves them.
- The base migration limits profile reads to the signed-in user's own row or an
  admin. This lets the existing admin screen list merchants while regular
  users cannot read other users' email addresses. Admin provisioning must be
  done as a trusted local/development database seed, never by signup.
- Policies and grants must be tested with two users and no session on an
  isolated local stack. A SQL file existing in Git does not mean its protections
  are active in any Supabase project.

## Tools and safe local setup

Last verified local setup: the GoCart Supabase stack ran on ports separate from
the existing `drupa` project; 15 migrations were recorded, SQL tests passed
(122 assertions across 6 files), database lint passed, and Edge Runtime 1.77.4
was used for local webhook checks. These are historical local validation
results, not proof of the current stack state. Flutter analysis and tests were
also previously reported passing. Check the local project identity and current
status before any database operation. No hosted project was modified.

Install only after you are comfortable with the explanation:

1. Install Docker Desktop for Windows and start it. It runs the local database
   and Supabase services in containers; it does not connect them to production.
2. Install the Supabase CLI (the earlier local setup note lists Scoop/npm
   options). Confirm `supabase --version` in a new terminal.
3. Deno is useful for running/checking Edge Functions locally. PostgreSQL tools
   such as `psql` are useful for direct local SQL work, but Supabase CLI's local
   database can be operated without separately installing them.
4. Review the migration history and any locally untracked migration files
   before treating the project as reproducible from Git. Starting local
   Supabase changes local machine state; it does not change a hosted project.

Do not use `supabase link`, `supabase db push`, a hosted SQL Editor, or Edge
Function deploy commands for this task. The screenshot provided earlier
showed a project named `main` marked **PRODUCTION**.

## Test evidence

- GoCart review on 2026-10-27: 142 focused mocked Node tests passed for
  Razorpay mode validation, order dispatch, payment validation, verification,
  webhook handling, reconciliation, and refund dispatch. Command:

  ```powershell
  node --experimental-strip-types --test supabase/functions/_shared/razorpay_mode.test.ts supabase/functions/_shared/razorpay_payment_validation.test.ts supabase/functions/_shared/razorpay_payment_collection_validation.test.ts supabase/functions/_shared/razorpay_order_dispatch.test.ts supabase/functions/_shared/verify_payment_handler.test.ts supabase/functions/_shared/razorpay_webhook_handler.test.ts supabase/functions/_shared/razorpay_reconciliation_handler.test.ts supabase/functions/_shared/razorpay_refund_dispatcher.test.ts
  ```
- On 2026-10-27, Flutter notification/payment model and screen tests passed (9),
  checkout/Razorpay/order-service tests passed (12), `flutter analyze --no-pub`
  passed, and the Dart no-write format check passed. The 142 mocked Node tests
  listed above also passed. SQL tests remain unverified because no approved
  isolated restored GoCart baseline is available.

- Flutter validation on 2026-10-14: `flutter analyze --no-pub` reported no
  issues; `flutter test --no-pub` passed all 18 tests. The suite covers search
  filter quoting, product pagination, test-payment response validation, and
  existing checkout/order behavior.
- Flutter web release build passed with synthetic configuration values; this
  verified compilation only and did not contact Supabase or Razorpay.
- Local database validation recorded earlier: 15 migrations, 122 SQL
  assertions across 6 files, and database lint passed. Independent-session
  payment/cancellation concurrency checks also passed. These were not rerun in
  this documentation/security pass.
- Edge Function validation on 2026-10-14: 66 mocked Node tests passed and
  local Edge Runtime 1.77.4 validated webhook signature and quarantine cases
  using synthetic data. No live Razorpay calls were made.
- No hosted Supabase project was accessed or modified. No live payment,
  provider refund, Firebase delivery, or production deployment was tested.
- Current labels: locally implemented; focused local Flutter and mocked Node
  validation passed; SQL tests unverified; Razorpay test-mode device validation
  pending; migrations and Edge Functions not deployed. Backup/restore evidence,
  restored-legacy migration testing, migration-history reconciliation, owner
  approval of exact SQL/deployment method, and postflight verification remain
  production blockers.
- Migration files still untracked must be included in a reviewed source change
  before another developer can reproduce the local schema from a clean clone.

## Beginner setup checklist

1. Review the complete migration/function diff and ensure all required files
   are tracked in the intended feature change; keep local Supabase metadata and
   credentials out of source control.
2. Re-run migrations, SQL tests, and database lint on an identified disposable
   local GoCart database without resetting it unless separately approved.
3. Agree the open business rules: multi-merchant fulfillment, cancellation and
   late-capture handling, return window, refund policy, commission rate/rounding,
   and payout eligibility.
4. Complete test-mode Razorpay device testing and interruption recovery without
   live payments; automated tests do not exercise the native SDK or provider API.
5. Configure an approved Firebase project and complete FCM token, server-send,
   and device lifecycle tests.
6. Implement reviews, commission snapshots and payouts once their business
   rules are approved.
7. Complete the release checklist: pagination, accessibility, slow-network and
   device tests, backup/restore drill, updated CI, and human review. Keep hosted
   migration and deployment steps for an approved release process.
