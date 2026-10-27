# Razorpay reconciliation holds

The reconciliation function reads the provider order and its payment collection. The collection is expected to contain every payment attempt linked to the order, together with `entity`, `count`, and `items`. A mismatch between the collection count, returned items, and the order's attempt count is treated as incomplete evidence.

The provider collection can contain multiple attempts. A captured payment accompanied by a `created`, `authorized`, or `failed` attempt is recorded for review and is not promoted through the normal paid path. Razorpay documents that a timed-out/failed payment can later be authorized, so a current `failed` sibling is not treated as conclusive while reconciling another capture. The handler does not cancel an authorization or issue a refund. Provider states and refund metadata that are missing, malformed, or contradictory also remain in review.

## Reservation handling

The local Razorpay Orders API contract does not establish a terminal order state that proves no payment can later be captured. The `record_authoritative_noncapture_and_release` RPC is therefore disabled by the forward migration. Caller booleans and an arbitrary evidence reference cannot mark an attempt noncaptured. The cancellation trigger is aligned with that restriction and accepts only no-attempt cancellation or proven pre-dispatch abandonment.

An expired reservation with a dispatched attempt, a historical `created` attempt, a pending or authorized payment, or an incomplete provider lookup stays active. Its stock and offer capacity remain reserved. The recovery reaper can still release a reservation with no payment attempt or a payment attempt proven to be abandoned before provider dispatch; those releases remain atomic and exactly once.

## Manual review

For an unresolved reservation, retain the order and reservation as held. An authorized financial operator should review the provider dashboard and, if the provider state is unclear, obtain confirmation through the provider's support process. Do not edit payment-attempt state, decrement or increment stock, change offer counters, or cancel the order directly to force a resolution.

Until a provider-supported terminal noncapture contract is established, record the case through the organization's approved financial incident process and leave the database reservation held. A future automated release path requires a server-only reconciliation operation that durably binds the order ID, provider order ID, verified terminal provider evidence, and evidence digest to a reconciliation result before the release transaction can consume it. No such terminal result is emitted by this implementation.

Late captures on already cancelled orders continue through the existing payment-review transition and must not reopen fulfillment.
