# Order Status and Local Development Notes

Updated: 2026-10-27

## Local Supabase setup

The repository has `supabase/config.toml`, but this machine does not currently
have the Supabase CLI, Docker, PostgreSQL, or Deno available. The config is
project-local and does not contain a hosted project reference. No `supabase
link`, hosted login, migration, or deployment was run.

To prepare an isolated local database on Windows:

1. Install and start Docker Desktop. Supabase's local stack needs a
   Docker-compatible runtime. Docker's current Windows WSL2 requirements
   include at least 8 GB of RAM, hardware virtualization, and WSL 2.1.5 or
   later ([Docker requirements](https://docs.docker.com/desktop/setup/install/windows-install/)).
2. If Scoop is installed, add Supabase's CLI bucket and install the stable CLI:

   ```powershell
   scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
   scoop install supabase
   ```

   Open a new terminal afterward. The official CLI guide also documents npm;
   npm-based CLI use requires Node.js 20 or later.
3. From the GoCart project root, check that `supabase --version` works and that
   Docker Desktop is running.
4. Review the migration history and proposed
   `20260926000000_gocart_base_schema.sql` in Git before starting the local
   stack. It fills the missing `profiles`, `products`, `cart_items`, and cart
   function foundation. It now has a non-recursive admin profile-read helper,
   product category/price checks, product-image storage setup, and exact policy
   names expected by later migrations. It has not been parsed or run against
   PostgreSQL. Do not run `supabase init` over the existing `supabase/`
   directory.
5. Once the base schema is present and reviewed, run `supabase start` from this
   project directory. It starts the local stack; it does not target a hosted
   project. Keep the printed local credentials private and use only the local
   URL in local Flutter configuration. `supabase stop` stops the local stack
   without resetting its data.

The local Supabase stack is for development only. Supabase documents that the
local stack is not production-hardened and should not be exposed to external
traffic.

## Merchant approval behavior

New merchants start with `merchant_status = 'pending'`. Signup now explains
that an administrator must approve the account and does not call
`approve_my_merchant_account()`. Login and app startup also block pending
merchants from the merchant dashboard. The database's product policies and
stock function remain the security boundary if a user bypasses the UI. The
admin-only path is `admin_set_merchant_status()`. The obsolete compatibility
RPC is removed by
`20261025140412_harden_merchant_approval_and_truncate.sql`.

## Existing status behavior

The current `change_order_status` database function permits:

- `pending -> paid`
- `paid -> shipped`
- `shipped -> delivered`
- `delivered -> return_requested`
- `pending -> cancelled`
- `paid -> cancelled`

The function is executable only by `service_role`. The `cancel_own_order`
wrapper is executable by authenticated users and delegates cancellation; the
status function checks that the order belongs to the caller. Cancellation
restores product stock and coupon usage in the same transaction. It does not
perform or record a refund for a paid order.

`verify-payment` checks the Razorpay checkout HMAC, authenticates the user,
checks order ownership, fetches the provider payment, and verifies captured
status, order association, amount, and currency before recording payment with
the service role. Local payment-attempt/refund ledgers and order-creation
recovery are in place. The native Flutter Razorpay Checkout screen and signed
webhook endpoint are implemented locally with mocked tests. No Razorpay
credentials or payments have been used to validate provider behavior, and the
Edge Functions and migrations have not been deployed. See
`DATABASE_AND_PAYMENT_GUIDE.md` for remaining gaps. Cancelling a paid order preserves its paid
payment status until a provider refund result is recorded. A captured payment
discovered after cancellation is stored for review rather than changing the
cancelled order to paid. Cancellation currently restores stock and offer usage
immediately, including for paid orders, while no provider refund is initiated.
The `paid -> shipped` transition does not currently check merchant ownership.
There is no return resolution transition.

The current merchant order-item read policy requires the account to remain a
merchant with approved status. Pending or suspended merchants and demoted
accounts do not retain access to historical item rows. Buyers retain access to
their own rows. The current application has no admin order-management screen;
administrators can read status-history rows under the existing policy, but do
not have corresponding all-order or all-item access. That policy mismatch is
left unchanged until an admin workflow is approved.

## In-app notifications

The existing admin inbox persists pending merchant-registration notices. A
newer local migration and Flutter inbox add merchant status/reinstatement,
order, and verified payment events. Notification reads are recipient-scoped;
event creation is tied to the status audit, reinstatement request, order, or
captured payment transaction. These additions have not been applied to a
database. Their pgTAP contract is
`supabase/tests/user_event_notifications.test.sql`; it has not been run.

## Safe history work prepared

Migration `20261013020000_add_order_status_history.sql` adds an append-only
history table and database triggers. The database records order creation and
each real status change in the same transaction as the order write. It derives
the actor from the authenticated Supabase identity and the `profiles.role` row;
service-role operations are recorded as `system` with no human actor ID.
Authenticated clients can read their own order history (admins can read all)
but cannot insert, update, or delete history or directly update orders. The
service API role also has no direct history-table insert grant; the trigger
function writes through its restricted database-owner context.

Existing orders are not backfilled with guessed actors. Their future status
changes will have a history entry containing their actual previous and new
status. The current transition graph is not changed by this migration.

The database contract test is at
`supabase/tests/order_status_history.test.sql`. It checks that the table and
triggers exist and that API clients lack direct write privileges. The complete
four-file local SQL suite passed with 87 assertions after the payment access
and merchant authorization migrations were applied to the local GoCart DB.

## Decisions requiring team-lead approval

These rules affect who can take actions and how money or goods are handled, so
they are intentionally not changed here:

1. **Orders with several merchants:** Should one order contain products from
   multiple merchants? If yes, should shipping state be tracked per order item
   or merchant shipment, or should checkout split the order?
2. **Delivery confirmation:** Who marks an order delivered: buyer, merchant,
   admin, or a trusted carrier/system integration?
3. **Returns:** What is the return window, when does it begin, and what quantity
   or item limits apply? Who can approve or reject a request?
4. **Paid-order cancellation/refunds:** Is cancellation allowed after payment,
   and what refund provider/process, timing, and failure state should be used?
5. **Buyer cancellation:** Until which order states or fulfillment events can a
   buyer cancel?
6. **Pending-payment expiry:** How long may an unpaid order reserve stock, and
   should expiry automatically cancel it or require buyer action?
7. **Inventory and offer restoration:** Is restoration immediate on
   cancellation, after refund confirmation, or only for orders not yet paid?
   Should returns restore stock or offer usage?
8. **Refund amounts and failures:** Are refunds full-only or partial? Who may
   request them, how should pending/unknown/failed refunds be retried, and when
   may fulfillment resume?
9. **Late capture after cancellation:** Who reviews a captured payment for a
   cancelled order, and should it be refunded, reinstated, or handled another
   way?

Until these are approved, do not enable new merchant shipping, delivery, return
resolution, or paid-order refund actions. Existing cancellation behavior is
documented above and should be reviewed before a development migration is
applied.
