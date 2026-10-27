begin;

select plan(25);

insert into auth.users (id, email) values
  ('30000000-0000-0000-0000-000000000001', 'payment-consistency@example.invalid');
insert into public.profiles (id, name, email, role) values
  ('30000000-0000-0000-0000-000000000001', 'Payment Consistency', 'ignored@example.invalid', 'user');
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '30000000-0000-0000-0000-000000000001', 'payment-consistency-product', 20, 20, 20, 7, 'Electronics'
);
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('CONSISTENCY10', 'percent', 10, 10, 0);
insert into public.cart_items (user_id, product_id, quantity)
select '30000000-0000-0000-0000-000000000001', id, 2
from public.products where name = 'payment-consistency-product';

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.checkout_place_order('CONSISTENCY10', 'payment-consistency-key-001');
reset role;

select is((select payment_status from public.orders where idempotency_key = 'payment-consistency-key-001'),
  'unpaid', 'checkout starts in the valid unpaid state');

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select lives_ok(
  $$do $claim$
  declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-consistency-key-001';
    select * into v_claim from public.claim_razorpay_order(
      v_order_id, '30000000-0000-0000-0000-000000000001');
    if v_claim.claim_state <> 'claimed' then raise exception 'expected new claim'; end if;
    perform public.complete_razorpay_order(v_order_id, v_claim.claim_token, 'rzp_consistency_order');
  end $claim$;$$,
  'provider order is associated with the local order before verification');
select throws_ok(
  $$update public.orders set payment_status = 'not_a_payment_state'
    where idempotency_key = 'payment-consistency-key-001'$$,
  '23514', null, 'invalid payment status is rejected by the CHECK constraint');
select throws_ok(
  $$select public.change_order_status(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-001'), 'paid')$$,
  'P0001', 'PAYMENT_CONFIRMATION_REQUIRES_VERIFIED_PAYMENT',
  'generic privileged status RPC cannot mark an order paid');
select throws_ok(
  $$update public.orders set status = 'paid', payment_status = 'paid'
    where idempotency_key = 'payment-consistency-key-001'$$,
  'P0001', 'PAYMENT_REQUIRES_VERIFIED_CAPTURE',
  'direct privileged update cannot mark an order paid without a captured ledger entry');
select lives_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-001'),
    '30000000-0000-0000-0000-000000000001', 'rzp_consistency_order',
    'rzp_consistency_payment', 3600, 'INR')$$,
  'verified-payment RPC records the captured payment and order transition atomically');
select is((select status from public.orders where idempotency_key = 'payment-consistency-key-001'),
  'paid', 'verified payment transitions fulfillment to paid');
select is((select payment_status from public.orders where idempotency_key = 'payment-consistency-key-001'),
  'paid', 'verified payment transitions payment status to paid');
select is(
  public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-001'),
    '30000000-0000-0000-0000-000000000001', 'rzp_consistency_order',
    'rzp_consistency_payment', 3600, 'INR'),
  'captured', 'duplicate verification returns the captured result');
select is((select count(*)::int from public.razorpay_payment_attempts
  where provider_payment_id = 'rzp_consistency_payment'),
  1, 'duplicate verification associates one provider payment');
select ok(position('for update' in lower(pg_get_functiondef(
  'public.record_verified_razorpay_payment(uuid,uuid,text,text,bigint,text)'::regprocedure))) > 0,
  'verification locks the order and attempt rows to serialize concurrent requests');
reset role;

-- Captured orders must not release stock or coupon usage through cancellation.
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-001'))$$,
  'P0001', 'PAYMENT_ALREADY_CAPTURED',
  'buyer cancellation cannot release a captured order reservation');
reset role;
select is((select stock from public.products where name = 'payment-consistency-product'),
  5, 'paid cancellation leaves reserved inventory unchanged');
select is((select used_count from public.offers where code = 'CONSISTENCY10'),
  1, 'paid cancellation leaves offer usage consumed');
select is((select count(*)::int from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'payment-consistency-key-001'),
  1, 'paid cancellation preserves the offer-redemption record');
select is((select payment_status from public.orders where idempotency_key = 'payment-consistency-key-001'),
  'paid', 'paid order remains paid after rejected cancellation');
select is((select status from public.orders where idempotency_key = 'payment-consistency-key-001'),
  'paid', 'paid order fulfillment state remains unchanged');

select ok(position('for update' in lower(pg_get_functiondef('public.change_order_status(uuid,text)'::regprocedure))) > 0,
  'cancellation transition locks the order row to serialize concurrent calls');
select ok(position('release_checkout_reservation' in lower(pg_get_functiondef(
  'public.cancel_own_order(uuid)'::regprocedure))) > 0,
  'buyer cancellation delegates to the reservation release contract');

-- Once provider-order creation has been claimed, cancellation is ambiguous and
-- must be rejected. The eventual verified capture settles the reservation.
insert into public.cart_items (user_id, product_id, quantity)
select '30000000-0000-0000-0000-000000000001', id, 2
from public.products where name = 'payment-consistency-product';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.checkout_place_order(null, 'payment-consistency-key-002');
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select lives_ok(
  $$do $late_claim$
  declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-consistency-key-002';
    select * into v_claim from public.claim_razorpay_order(
      v_order_id, '30000000-0000-0000-0000-000000000001');
    perform public.complete_razorpay_order(v_order_id, v_claim.claim_token, 'rzp_late_order');
  end $late_claim$;$$,
  'second test order is ready for a late-capture scenario');
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select throws_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-002'))$$,
  'P0001', 'PAYMENT_RECONCILIATION_REQUIRED',
  'an order with a provider attempt cannot release its reservation');
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select is(
  public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-consistency-key-002'),
    '30000000-0000-0000-0000-000000000001', 'rzp_late_order',
    'rzp_late_payment', 4000, 'INR'),
  'captured', 'verified capture settles after a cancellation request was blocked');
select is((select status from public.orders where idempotency_key = 'payment-consistency-key-002'),
  'paid', 'verified payment moves the still-pending order to paid');
select is((select payment_status from public.orders where idempotency_key = 'payment-consistency-key-002'),
  'paid', 'verified payment records the paid state');
select is((select state from public.razorpay_payment_attempts a
  join public.orders o on o.id = a.order_id
  where o.idempotency_key = 'payment-consistency-key-002'),
  'captured', 'verified capture is retained in the attempt ledger');
reset role;

select * from finish();
rollback;
