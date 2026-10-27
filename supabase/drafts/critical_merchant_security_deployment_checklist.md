# Critical Merchant Security Patch — Deployment Checklist

**Project:** GoCart
**Verified Supabase reference:** `jqulrjrpzdozhlxeuefy`
**Status:** Not deployed; read-only review and planning only.

## Configuration verification

- [x] The Supabase Dashboard Data API settings were inspected for the verified GoCart project.
- [x] Exposed schemas listed: `graphql_public`, `public`.
- [x] `gocart_private` is not listed as an exposed schema.
- [x] Extra search path listed: `public`, `extensions`.
- [x] No project settings were changed.

This confirms `gocart_private` is not exposed through the Data API's exposed-schema list. It does not authorize applying the candidate SQL.

## Required before any live deployment

- [ ] Obtain an owner-approved backup and verify the restore path.
- [ ] Test `supabase/drafts/critical_merchant_security_patch.sql` against an isolated, restored copy of the legacy GoCart schema. Do not create or start a test database without explicit owner approval.
- [ ] Obtain owner approval for the exact SQL and controlled deployment method.

## Deployment constraints

- Keep the candidate patch outside the active migration chain until the migration-history mismatch has a separately approved resolution.
- Do not replay the local migration chain or mark migrations applied to bypass the empty live migration history.
- Do not deploy with `supabase db push`, migration repair, or database reset.
- After the restored-copy test passes and the owner approves deployment, verify the live project reference again before any approved write.

## Current state

- The candidate patch and its regression tests have not been applied or run against live GoCart.
- No live database writes, migrations, deployments, or settings changes were performed for this checklist update.

## Local security review record

This section describes local SQL and application code only. It is not evidence
that production has been repaired.

### Threat model and database enforcement

- The critical privilege boundary is PostgreSQL: authenticated and anonymous
  callers must not execute `approve_my_merchant_account()`, and authenticated
  users must not directly update `profiles.role` or
  `profiles.merchant_status`. The reviewed draft now revokes these direct
  profile update privileges while retaining the app's name-only profile edit.
- The signup screen inserts only identity fields and role; the existing
  profile trigger assigns merchant `pending` status. The app does not call the
  self-approval RPC. Login and the reinstatement UI/service remain separate.
- The draft adds a restrictive product SELECT policy. Its helper allows a
  merchant to inspect their own listing, admins to inspect listings, and
  public customers to see approved merchants' products. The restrictive
  policy is intended to constrain the legacy permissive catalog policy.
- Before-cart insert/update and order-item insert triggers recheck status
  inside the write transaction. Their `FOR SHARE` lock on the merchant profile
  serializes each write against a status update: a suspension committed first
  causes the write to fail; a checkout holding the share lock finishes before
  the suspension can commit. Failed legacy `place_demo_order()` statements
  roll back the order, stock update, and cart deletion together.
- The local notification repair draft creates a pending-registration alert
  from a profile trigger and deduplicates it with a unique
  `(merchant_id,event_type)` key. Status changes resolve that registration
  alert in the same transaction. Separate approval/suspension event alerts
  are not established by that design. Its schema and functions are not in the
  verified live baseline.

### Regression coverage and limitations

- `supabase/tests/critical_merchant_security_patch.test.sql` targets the
  legacy demo-checkout schema. It checks client self-approval denial, direct
  profile privilege denial, admin approval, own/admin product visibility,
  non-admin approval denial, suspended product hiding, cart add and quantity-
  update rejection, and legacy checkout rollback (order header, stock, and
  cart row).
- Its two-session concurrency case is manual guidance, not an automated
  regression. Automated coverage for concurrent stock contention remains
  required on a restored legacy copy.
- `supabase/tests/merchant_suspension.test.sql` targets a newer checkout
  schema and is not proof of legacy `place_demo_order()` behavior.
- Local notification and reinstatement migrations/tests depend on schema and
  function contracts absent from the verified live baseline; do not run them
  as a substitute for legacy-baseline tests.
- No database test has been run. There is no explicitly owner-approved
  restored baseline available. Focused Flutter, analyzer, format and mocked
  Node validation completed on 2026-10-27; exact commands and results are
  recorded in `DATABASE_AND_PAYMENT_GUIDE.md`. No SQL test is claimed as
  passing.

### Migration and review risks

- The live migration-history result is empty even though the legacy schema is
  populated. The historical local profile/cart hardening migration grants
  authenticated execution of `approve_my_merchant_account()` again. Replaying
  the local chain or treating file presence as applied would be unsafe.
- Keep the critical patch and broad notification repair outside the active
  chain until schema reconciliation is approved. Reconcile against catalog
  definitions and preserve existing orders, carts, stock, and payment states.
- The local admin dashboard currently calls the three-argument
  `admin_set_merchant_status(..., p_reason)` contract; the verified legacy
  baseline has the two-argument function. The broad repair draft changes this
  contract. Keep the Flutter reason parameter. Before deployment, inspect all
  live dependencies and overloads on a restored copy, then review the repair
  migration's replacement of the legacy function with the internally
  admin-authorized, reason-aware three-argument function. Verify that the
  status reason is stored in the audit row, grants remain authenticated-only,
  and the resulting overload contract matches the Flutter call. Abort on
  unknown dependents; do not simply add a defaulted overload or drop the old
  signature without dependency evidence.
- The new local `20261027130000_user_event_notifications.sql` depends on the
  reconciled order/payment schema plus merchant audit and reinstatement
  objects. It must follow those dependencies on a restored copy; it has not
  been applied or database-tested.
- Production remains vulnerable until an approved, tested SQL change is
  applied and postflight-verified. Local tests or source review do not change
  that status.

## Validation commands

## Final migration compatibility review (2026-10-27)

These are local-file comparisons against the previously verified legacy GoCart
schema; no remote inspection or write was performed in this review.

### Known legacy contracts and incompatibilities

- The verified legacy checkout exposes `add_to_cart(bigint,integer)`,
  `update_cart_quantity(bigint,integer)`, and `place_demo_order()`. The focused
  [critical patch](critical_merchant_security_patch.sql) explicitly requires
  those signatures plus `products(id,merchant_id)`,
  `cart_items(product_id,quantity)`, and `order_items(product_id,merchant_id)`.
  Its trigger guards can protect cart insert/update and legacy checkout's
  order-item inserts, but the draft must first be tested against a restored
  copy because its preflight does not establish every legacy function body's
  locking/rollback behavior.
- The local payment/checkout chain beginning at
  `supabase/migrations/20261008000000_server_side_checkout.sql` and later
  migrations assumes the newer server-side order, reservation, idempotency,
  payment-attempt, refund, and webhook contracts. The known live database uses
  the older demo-checkout order/payment shape. Files from
  `20261015000000_payment_state_and_recovery.sql` through
  `20261027100000_distinguish_payment_review_outcomes.sql` have dependent
  tables/functions and ordering assumptions; they are not a compatible
  replay unit for the legacy database. Preserve existing orders, order items,
  stock, carts, and payment states while mapping the legacy schema explicitly.
- The original 20261008 draft mapped `placed`/`processing` to `paid` and
  `demo_paid` to `paid`, which is unsafe without capture evidence. The current
  local file removes those updates and now takes `ACCESS EXCLUSIVE` locks and
  aborts before DDL if it finds `payment_method='demo'`, `payment_status=
  'demo_paid'`, `status in ('placed','processing')`, or an inbound foreign key
  to `order_items.id`. This is a fail-closed guard, not reconciliation. The
  migration still renames `buyer_id` to `user_id` and `total` to `total_amount`,
  narrows numeric precision, and replaces bigint `order_items.id` with UUID
  while preserving the prior value as `legacy_id`. Its preflight does not
  inventory dependent views, indexes, trigger bodies, function bodies, or
  external clients. Check those on the restored baseline before any key
  transition. The later 202610261100 quarantine cannot reconstruct an earlier
  status that has already been overwritten by any previously applied version.
- `20261025140412_harden_merchant_approval_and_truncate.sql` expects the newer
  three-argument `admin_set_merchant_status(uuid,text,text)` and related admin
  helper contract. It drops `approve_my_merchant_account()` and restricts
  profile updates, but it cannot by itself reconcile the live two-argument
  `admin_set_merchant_status(uuid,text)` signature.
- `20261027120000_merchant_reinstatement_lifecycle.sql` has a fail-closed
  preflight for the three-argument reason-aware RPC, `merchant_status_audit`,
  existing admin notification objects, the hardened profile trigger and its
  helper. It creates `merchant_reinstatement_requests`, status/admin RPCs and
  their grants/RLS, with status audit insertion inside the status-change
  transaction. It will fail against the known legacy schema until those
  prerequisites are reconciled. Keep `p_reason`; do not add a defaulted
  overload or silently map to the old two-argument RPC.
- The broad `supabase/drafts/20261027110000_repair_merchant_approval_notifications.sql`
  is a legacy starting-point repair draft, not an active migration. It checks
  the two-argument RPC, expected profile trigger/function contracts, grants,
  policies and object conflicts before creating audit and admin-notification
  tables/triggers and replacing the status RPC. Its `DROP FUNCTION ...
  RESTRICT` intentionally aborts if dependencies exist. Review its full
  preflight and every function/policy dependency against a restored baseline;
  do not run it as a blind first migration.
- `20261027130000_user_event_notifications.sql` follows the lifecycle schema.
  Its preflight requires `profiles(id,role)`,
  `merchant_status_audit(id,merchant_id,old_status,new_status)`,
  `merchant_reinstatement_requests(id,merchant_id,request_status)`, modern
  `orders(id,user_id,status,payment_status,razorpay_order_id)`,
  `order_items(order_id,merchant_id)`, and
  `razorpay_payment_attempts(order_id,provider_payment_id,state)`. Legacy
  orders do not satisfy the modern notification contract. The migration adds
  recipient-scoped RLS, a mark-read RPC and triggers on the audit,
  reinstatement, order-item, order-update and payment-attempt tables. Those
  triggers must be installed only after the exact columns, referenced
  functions, and capture transaction ordering are established. The payment
  notice now observes the order's paid transition after the capture RPC has
  updated the attempt, and requires `has_verified_razorpay_capture(order_id)`;
  the former attempt-row trigger checked for an already-paid order too early
  and therefore skipped notifications in the current RPC's update order.
  This correction is only statically reviewed. Its unique recipient/event/entity key makes retries idempotent. Registration alerts
  remain in the separate `admin_merchant_notifications` design from the
  legacy repair draft; the user-event migration itself does not create that
  registration inbox.
- `20260926000000_gocart_base_schema.sql` and
  `20260927000000_harden_profile_and_cart_writes.sql` both grant
  `authenticated` execution of `approve_my_merchant_account()`. Replaying
  either after a revocation restores the self-approval RPC privilege. The
  later `20261025140412` and `20261025160000` migrations revoke/drop it, but
  their order and schema prerequisites cannot be inferred from the empty live
  migration history.
- The 20261008 checkout migration and the early payment-state migration define
  privileged status-changing paths that can request `paid`. The later verified
  payment transition guard blocks those transitions unless the captured
  attempt matches. Treat those migrations as one reviewed release boundary;
  do not expose any service-role checkout/payment caller in the gap before the
  guard is installed and postflight-checked.
- `20261015090000_enforce_suspended_merchant_visibility.sql`,
  `20261015110000_correct_suspended_merchant_visibility.sql`, and
  `20261015130000_reconcile_merchant_suspension_contract.sql` successively
  add/correct restrictive product visibility and audit/policy assumptions.
  They depend on the newer merchant/audit contracts and policy names; do not
  assume they protect the legacy catalog or stack them without inspecting
  existing permissive policies and helper ownership/RLS bypass behavior.

### Forward-only deployment sequence proposal

1. Obtain owner approval for a backup and demonstrate a restore. Record
   schema-only and data-recovery evidence for profiles, products, carts,
   orders, order items and any legacy payment records; retain row counts,
   keys, constraints, indexes, policies, grants, function definitions and
   trigger definitions. No destructive rollback of order/payment history.
2. On that approved restored copy, inventory exact legacy contracts,
   dependencies, duplicate/orphan data and status values. Build one reviewed
   reconciliation baseline from the actual schema rather than replaying the
   timestamp chain or repairing migration history.
3. Apply/test the smallest merchant foundation first: force signup to pending;
   revoke/drop all effective self-approval overload grants; prevent direct
   role/status profile updates; define a reason-aware admin status operation
   with an internal admin check and transactional audit. Preserve the
   three-argument Flutter contract and resolve the old two-argument RPC only
   after dependency inspection.
4. Add restrictive approved-merchant product visibility (including explicit
   owner/admin behavior), then transaction-locked cart insert/update guards
   and a legacy checkout order-item guard. Test suspension races, rollback,
   existing cart behavior and checkout before moving on.
5. Reconcile legacy orders/payment state into the newer checkout/payment
   contract only with a documented mapping and no inferred provider-paid
   status. Preserve IDs/history; add constraints/indexes only after duplicate,
   null and orphan checks. Verify payment claim/capture/recovery RPCs and
   idempotency against the preserved history.
6. Add lifecycle/reinstatement objects and admin registration notifications
   after the approval foundation; then add `20261027130000`-equivalent user
   notifications after modern order/payment/audit schemas and capture trigger
   order exist. Verify recipient RLS, function grants, search paths, unique
   event keys and repeat/concurrent event handling.
7. Run restored-copy SQL regressions, two-session races, postflight catalog and
   data-integrity comparisons, then owner review of the exact forward SQL,
   rollback/containment steps, deployment window and monitoring. Only then
   request a separate explicit live deployment approval. Prefer forward
   containment (disable the affected RPC/path) to destructive rollback; never
   delete or rewrite order/payment history to reverse a deployment.

### Required schema and dependency contracts

Treat these as local application contracts to reconcile, not as permission to
replay the timestamped chain.

- **Legacy order rows:** `orders(id uuid,buyer_id uuid,status,payment_method,
  payment_status,total numeric(12,2),created_at)` with `demo_paid` history;
  `order_items(id bigint,order_id uuid,product_id bigint,merchant_id uuid,
  product_name,unit_price numeric(12,2),quantity,line_total,created_at)`;
  `products.id` and `cart_items.id/product_id` are bigint. Preserve order UUIDs,
  old order-item IDs, product snapshots, totals, carts, stock and status
  meaning. Verify all existing FKs before changing any key.
- **Orders expected by current RPCs/notifications:** `orders.id uuid`,
  `user_id uuid`, `total_amount numeric`, `status`, `payment_status`,
  `payment_method`, `idempotency_key`, `razorpay_order_id`, and timestamps.
  Local 20261008 renames buyer/total and changes the historical state values;
  a safe forward migration must map/copy, validate counts/totals and retain
  demo records without marking them provider-paid. Do not rely on an unreviewed
  rename or narrowing cast.
  **Do not replay the current 20261008 migration against the known legacy
  baseline without first satisfying its new fail-closed preflight:** it
  previously changed `placed`/`processing` statuses to `paid` and changed
  `demo_paid` to `paid`. The migration now locks orders and order items, then
  aborts before DDL if any legacy demo/payment-state rows or inbound foreign
  keys to `order_items.id` exist. The later 202610261100 quarantine runs
  only after earlier payment constraints and the 202610151000 analytics
  function; it snapshots the already-transformed state, so it cannot restore
  the original `placed` versus `processing` distinction. Consequently demo
  history may be counted as paid sales before quarantine. Keep the full chain
  blocked until an owner-approved restored copy proves an alternative,
  additive forward reconciliation that preserves IDs, status history, totals,
  and `demo_paid` semantics and never grants paid status without capture
  evidence. The preflight is a local safety guard, not a legacy reconciliation
  or proof that the remainder of the migration chain is compatible. Do not
  edit/replay migration history to mask this incompatibility.
- **Checkout RPC:** current local path uses authenticated
  `checkout_place_order` with the buyer-bound idempotency contract (the local
  chain defines `place_order(text,text)`, authenticated
  `checkout_place_order(text,text)`, and later
  `checkout_place_order_cached(text,text)`). The wrapper must authoritatively
  calculate from cart/product rows, lock products before cart rows in stable
  order, reject pending/suspended merchants, and atomically write pending order,
  item snapshots, inventory reservation and cart/idempotency state. Verify the
  exact Flutter Edge caller signature before granting `authenticated` execute.
- **Durable idempotency:** `idempotency_keys` stores key, user, operation,
  resource/order, response payload, created/completed times, claim token and
  lease expiry with constrained operation values and no direct client grants.
  Checkout, provider-order creation and payment verification use separate key
  scopes. Cached response RPCs must reject key/user/operation reuse and make
  retries return the original result.
- **Payment ledger:** `razorpay_payment_attempts` has UUID identity, unique
  order/buyer links, `expected_amount_paise bigint`, `currency='INR'`, constrained
  `state`, claim/lease tokens, unique provider order/payment IDs, timestamps,
  dispatch marker and recovery evidence. Later files add fields such as
  `dispatch_started_at`, `claim_lease_expires_at`, noncapture evidence and
  claim metadata. `razorpay_refunds` and `razorpay_webhook_events` also exist in
  the local design; all ledgers require RLS enabled and direct client grants
  revoked. Backfill any legacy provider order mapping as `created`, never as
  captured/paid.
- **Payment reconciliation evidence:** `razorpay_payment_reconciliation_runs`
  is required by `reconcile-razorpay-payment` and records a fenced run,
  decision, provider counts/status, evidence digest/summary and cached response.
  It also has RLS and no direct API grants. Refund webhook handling additionally
  depends on `razorpay_refunds` and `razorpay_refund_webhook_reconciliation`
  plus the refund-intent/dispatch/result RPC family; this is a separate,
  optional rollout after charge verification and order-state integrity. No
  refund API operation is required or authorized for initial test checkout.
- **Status/payment history:** `order_status_history` keeps order ID, prior/new
  state, timestamp, actor and role under buyer/admin read RLS. The additive
  `order_payment_integrity_events` ledger records audited quarantine or later
  reconciliation of legacy demo payment states. Preserve append-only evidence;
  do not reinterpret legacy rows during schema conversion.
- **Required RPCs (grant by caller purpose):** authenticated checkout uses
  `checkout_place_order(text,text)` and `checkout_place_order_cached(text,text)`;
  Edge/server calls use
  `claim_razorpay_order_with_key_recoverable(uuid,uuid,text)`,
  `cache_razorpay_order_response(uuid,text,jsonb)`,
  `complete_razorpay_order_cached(uuid,uuid,text,text,jsonb)`,
  `mark_razorpay_order_dispatch_started(uuid,uuid)`,
  `mark_razorpay_order_recovery(uuid,uuid)`;
  `claim_payment_verification(uuid,uuid,text)`,
  `cache_payment_verification_response(uuid,uuid,text,uuid,jsonb)`,
  `release_payment_verification_claim(text,uuid)`;
  `record_verified_razorpay_payment(uuid,uuid,text,text,bigint,text)`;
  `record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text,text)`;
  reconciliation `claim_razorpay_payment_reconciliation(uuid,text)`,
  `finish_razorpay_payment_reconciliation(uuid,uuid,text,text,integer,integer,text,jsonb,text,integer,jsonb)`,
  `record_reconciled_razorpay_capture(uuid,uuid,text,bigint,text,integer,integer,text,jsonb)`; webhook
  `claim_razorpay_webhook_event(text,text,text)` and
  `finish_razorpay_webhook_event(text,uuid,text,text)`; reservation
  `consume_checkout_reservation(uuid)` is trigger/internal only,
  `release_checkout_reservation(uuid)` checks owner/service authorization, and
  `reap_expired_checkout_reservations(integer)` is service-only. Keep
  service-only grants for provider-evidence and ledger mutation RPCs, fixed
  `search_path`, internal role checks and SECURITY DEFINER owner privileges.
  `record_verified_razorpay_payment` must
  lock order and attempt, validate buyer/provider IDs, exact amount/currency
  and captured evidence, then atomically transition attempt and order. An
  order trigger must reject a direct/unverified transition to paid.
- **Webhook/event idempotency:** `razorpay_webhook_events` requires event ID
  primary key, type/entity metadata, state, timestamps, error code, lease token,
  lease expiry and attempt count. Claim locks and deduplicates event ID, rejects
  conflicting metadata, and makes interrupted leases retryable. Verify the
  exact raw body signature before claiming. Repeated/out-of-order events must
  fetch/reconcile authoritative provider state and may not repeat payment,
  stock or reservation effects.
- **Inventory reservation:** `checkout_reservations` and
  `checkout_reservation_items` link orders, order items, cart lines, products,
  quantity and active/consumed/released states; active cart-line uniqueness
  prevents double reserve. Order/order-item triggers create ledger rows;
  verified capture consumes them atomically. Reapers/release RPCs may release
  only states proven safe; uncertain dispatched/authorized attempts retain
  reservation. Failed checkout must roll back order, stock/reservation and
  cart effects together.
- **RLS/triggers/grants:** preserve buyer-owned order reads and buyer/merchant
  order-item reads; remove broad legacy catalog policies and require approved
  merchant visibility with owner/admin exceptions. Keep RLS on orders,
  order_items, products and cart_items; direct order, stock and ledger writes
  remain revoked. Install merchant status guards before enabling new checkout.
  The checkout migration defines `Users can view own orders`, `Users can view
  own order items`, `Users can view own cart`, `Catalog is readable`, merchant
  product insert/update policies, active-offer reads and own-redemption reads;
  these names/expressions must be reconciled against legacy policies instead of
  blindly dropped/recreated. Reservation triggers are
  `orders_create_checkout_reservation`,
  `order_items_attach_checkout_reservation`,
  `cart_items_preserve_checkout_reservation`,
  `cart_items_guard_reserved_quantity`,
  `checkout_reservations_sync_items`,
  `orders_consume_checkout_reservation`, and
  `orders_guard_checkout_cancellation`. Payment triggers are
  `orders_require_verified_payment` and
  `orders_audit_legacy_payment_reconciliation`. All trigger functions should
  be non-client executable, fixed-search-path SECURITY DEFINER only where
  required, and owned by a role with the minimum table/RLS privileges.
  Keep the three-argument
  `admin_set_merchant_status(uuid,text,text)` with PostgreSQL admin check,
  persisted reason and transactional audit; revoke/drop every self-approval
  overload and privileged profile UPDATE grant.
- **Notifications:** only after profiles, `merchant_status_audit`,
  `merchant_reinstatement_requests`, modern orders/order_items and payment
  attempts exist. `user_notifications` uses recipient-scoped SELECT RLS,
  authenticated own-row mark-read RPC, no direct client writes, private trigger
  helpers and unique `(recipient_id,event_type,entity_type,entity_id)` key.
  The capture trigger follows the verified capture RPC's order update then
  attempt-to-captured update, verifies the order is already paid, and inserts
  in the same transaction. Unique event keys protect retries. Registration
  alerts remain the distinct admin inbox with separate admin-only RLS/grants.

### Preflight/postflight evidence required

- On the owner-approved restored legacy copy, inventory aggregate counts and
  key ranges for profiles/products/cart/orders/order_items/payment records;
  nulls, duplicate and orphan keys; status distributions; totals; every PK,
  FK (including inbound), index, policy, grant, function overload/dependency,
  owner/search_path/security mode and trigger state. Do not include personal
  records in reports.
- Prove old-to-new order/user/total mapping, historical `demo_paid` semantics,
  order-item key preservation, snapshot totals, and stock/cart invariants before
  cutover. Compare counts and monetary aggregates after each backfill.
- After each stage verify RPC signatures/effective grants, RLS policies,
  trigger enablement, unique constraints, no direct paid transition, and
  captured payment matching order/attempt IDs and amount/currency. Verify
  repeat webhook and retry produce no duplicate state, stock, or notification
  effects.
- Require owner approval for backup plus restore drill, exact forward SQL,
  deployment window and containment plan. Contain by disabling the affected
  path or applying a reviewed forward correction; do not erase/rewrite order,
  payment, webhook, stock or audit history as rollback.

### Minimum forward deployment sequence

This is an ordering plan, not an executable migration approval. Do not replay
the timestamped chain against the legacy project.

1. Obtain the approved backup and restore drill; record the exact legacy
   catalog, foreign keys (including inbound order-item references), constraints,
   grants, policies, function overloads, triggers, aggregate counts and status
   distributions on that isolated copy.
2. On that copy, finalize a data-preserving legacy bridge. Keep the original
   order IDs, order-item IDs, buyer/total values, carts, stock, snapshots, and
   historical demo statuses. Preserve `demo_paid` as demo-only. Add compatible
   payment fields/ledgers without treating legacy order values or demo markers
   as provider evidence. Validate all mappings and abort on ambiguous rows.
3. Install the merchant authorization/audit foundation and restrictive
   approved-merchant product visibility plus cart and checkout guards. Remove
   self-approval and direct privileged profile updates; retain owner/admin
   listing access and the reason-aware admin status operation.
4. Add server-only payment claim, verified-capture, webhook-idempotency, and
   recovery operations with a database guard that rejects paid transitions
   without matching captured evidence. Preserve existing order/payment history.
5. Add reservation/stock and checkout transaction changes only after their
   exact legacy RPC signatures and locking behavior pass the isolated
   concurrency and rollback tests.
6. Add merchant lifecycle/admin notification and reinstatement objects, then
   recipient-scoped user notifications and verified-payment triggers. Keep
   registration alerts distinct from merchant/buyer event notifications.
7. Deploy Edge Functions only after SQL postflight succeeds; configure
   test-mode secrets, then verify test checkout/webhooks in the approved test
   environment. Production rollout requires separate explicit approval.

No executable full-schema migration is approved by this review: the known
legacy order transformation is lossy, migration history is empty despite
existing tables, and no owner-approved restored legacy baseline is available
to validate an alternative. The local security patch remains a draft, while
the payment, visibility, lifecycle, and notification migrations remain
unapplied local definitions.

### Razorpay test-mode Android checklist

- [ ] Use Razorpay test-mode credentials only. Configure the existing Edge
  Function secrets `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, and
  `RAZORPAY_WEBHOOK_SECRET` in an approved non-production test deployment;
  provide only the public test `RAZORPAY_KEY_ID` to Flutter using the app's
  existing configuration. Do not put secret values in Flutter, `.env` files,
  logs, or screenshots. Do not deploy from this review.
- [ ] Confirm the app launches the native checkout with a server-created order
  and server-calculated amount. Test success return and app lifecycle
  interruption/relaunch; client callbacks alone must not mark an order paid.
- [ ] Confirm the verification endpoint checks checkout signature and fetches
  matching captured payment/order IDs, amount and INR before recording paid.
- [ ] In a separately approved test deployment, configure the webhook URL and
  test secret in Razorpay's test-mode dashboard. Deliver a signed test event;
  confirm raw-body signature validation and durable event processing.
- [ ] Redeliver the same event and confirm idempotent handling; exercise
  duplicate/conflicting deliveries and reconciliation review behavior.
- [ ] Exercise failed, cancelled, timed-out, authorized-only and interrupted
  payments; verify recovery does not falsely mark paid or release stock when
  provider outcome is uncertain.
- [ ] Compare order, payment-attempt, reservation/stock and notification
  states after each outcome. Use provider test events/credentials only; do not
  perform a real payment or refund.

### Current readiness labels

- **Locally implemented:** Razorpay handlers/client flow, local merchant
  security drafts, lifecycle and notification migrations/UI.
- **Locally tested:** 142 mocked Razorpay Node tests; a prior focused Flutter
  run completed with 40 tests plus 2 admin AppBar tests, and Flutter analysis
  passed on 2026-10-27. The latest Razorpay Node rerun also passed 142 tests.
  Flutter analysis and focused Flutter test reruns in the current review
  produced no output and were interrupted; those reruns are incomplete.
- **SQL tests unverified:** no owner-approved restored legacy baseline was
  available; no SQL regression was run.
- **Test-mode device validation pending:** no Android emulator/device or
  Razorpay test credentials/provider calls were used.
- **Not deployed:** no database migrations or Edge Functions deployed; no
  live database operation occurred in this review.
- **Production blockers:** verified backup/restore, restored-legacy
  compatibility/regression testing, migration-history reconciliation, exact
  SQL and deployment-method owner approval, and postflight verification.

The focused Razorpay handler tests run without Supabase or provider traffic:

```powershell
node --experimental-strip-types --test supabase/functions/_shared/razorpay_mode.test.ts supabase/functions/_shared/razorpay_payment_validation.test.ts supabase/functions/_shared/razorpay_payment_collection_validation.test.ts supabase/functions/_shared/razorpay_order_dispatch.test.ts supabase/functions/_shared/verify_payment_handler.test.ts supabase/functions/_shared/razorpay_webhook_handler.test.ts supabase/functions/_shared/razorpay_reconciliation_handler.test.ts supabase/functions/_shared/razorpay_refund_dispatcher.test.ts
```

On 2026-10-27, Flutter notification/payment model and screen tests passed (9),
checkout/Razorpay/order-service tests passed (12), `flutter analyze --no-pub`
passed, and Dart's no-write format check passed. Razorpay mocked Node tests
passed (142). These results do not replace database tests, which require the
approved isolated restored copy described above.

Run the database regression only after an owner has approved and identified an
isolated restored legacy GoCart copy. Do not substitute the live URL:

```powershell
$env:RESTORED_GOCART_DB_URL = '<owner-provided restored-copy connection string>'
psql $env:RESTORED_GOCART_DB_URL -v ON_ERROR_STOP=1 -f supabase/drafts/critical_merchant_security_patch.sql
psql $env:RESTORED_GOCART_DB_URL -v ON_ERROR_STOP=1 -f supabase/tests/critical_merchant_security_patch.test.sql
```

These commands apply the draft only to the explicitly approved restored copy;
they are not live deployment instructions. The local Flutter UI/model checks
can be run separately:

```powershell
flutter test test/merchant_status_action_button_test.dart test/merchant_reinstatement_request_test.dart
```

The Flutter command was attempted during this review, produced no output for
over 30 seconds, and was interrupted. No successful test result is claimed.
