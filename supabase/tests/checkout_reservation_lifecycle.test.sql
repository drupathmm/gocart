begin;

select plan(89);

select ok(to_regclass('public.checkout_reservations') is not null,
  'checkout reservation ledger exists');
select ok(to_regclass('public.checkout_reservation_items') is not null,
  'checkout reservation item ledger exists');
select ok(to_regclass('public.offer_redemption_history') is not null,
  'released offer redemptions have a history ledger');
select ok(exists (
  select 1 from pg_indexes
  where schemaname = 'public'
    and indexname = 'checkout_reservation_items_one_active_cart_line_uidx'
), 'one active reservation per cart line has a unique index');
select ok((select relrowsecurity from pg_class
  where oid = 'public.checkout_reservations'::regclass),
  'reservation ledger has RLS enabled');
select ok((select relrowsecurity from pg_class
  where oid = 'public.checkout_reservation_items'::regclass),
  'reservation item ledger has RLS enabled');
select ok(not has_table_privilege('authenticated', 'public.checkout_reservations', 'SELECT'),
  'authenticated clients cannot read reservation internals');
select ok(not has_table_privilege('authenticated', 'public.checkout_reservations', 'INSERT'),
  'authenticated clients cannot create reservations directly');
select ok(not has_table_privilege('authenticated', 'public.offer_redemption_history', 'SELECT'),
  'authenticated clients cannot read the private redemption history ledger');
select ok(has_function_privilege('authenticated',
  'public.release_checkout_reservation(uuid)', 'EXECUTE'),
  'authenticated callers can invoke the owner-checked cancellation contract');
select ok(has_function_privilege('service_role',
  'public.release_checkout_reservation(uuid)', 'EXECUTE'),
  'service role can invoke the guarded release contract');
select ok(not has_function_privilege('anon',
  'public.release_checkout_reservation(uuid)', 'EXECUTE'),
  'anonymous callers cannot release reservations');

insert into auth.users (id, email) values
  ('40000000-0000-0000-0000-000000000001', 'reservation-buyer@example.invalid'),
  ('40000000-0000-0000-0000-000000000002', 'other-reservation-buyer@example.invalid');
insert into public.profiles (id, name, email, role) values
  ('40000000-0000-0000-0000-000000000001', 'Reservation Buyer', 'ignored-1@example.invalid', 'user'),
  ('40000000-0000-0000-0000-000000000002', 'Other Buyer', 'ignored-2@example.invalid', 'user');
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '40000000-0000-0000-0000-000000000001', 'reservation-lifecycle-product', 20, 20, 20, 7, 'Electronics'
);
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values
  ('RESERVE10', 'percent', 10, 5, 0),
  ('RELEASE10', 'percent', 10, 5, 0);
select throws_ok(
  $$insert into public.offers (code, discount_type, discount_value)
    values ('INVALID101', 'percent', 101)$$,
  '23514', null, 'percentage offers above 100 percent are rejected'
);
insert into public.cart_items (user_id, product_id, quantity)
select '40000000-0000-0000-0000-000000000001', id, 2
from public.products where name = 'reservation-lifecycle-product';

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.checkout_place_order('RESERVE10', 'reservation-test-key-001')$$,
  'checkout creates an order while retaining cart rows');
reset role;
select is((select total_amount from public.orders
  where idempotency_key = 'reservation-test-key-001'),
  36.00::numeric, 'percentage coupon discount is calculated from the server subtotal');

select is((select count(*)::integer from public.orders
  where idempotency_key = 'reservation-test-key-001'), 1,
  'the first idempotency key creates one order');
select is((select count(*)::integer from public.cart_items ci
  join public.orders o on o.user_id = ci.user_id
  where o.idempotency_key = 'reservation-test-key-001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'pending checkout preserves the cart row');
select is((select ci.quantity from public.cart_items ci
  join public.orders o on o.user_id = ci.user_id
  where o.idempotency_key = 'reservation-test-key-001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  2, 'pending checkout preserves the cart quantity');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'checkout reserves inventory once');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-001'),
  'active', 'new checkout has an active reservation');
select is((select count(*)::integer from public.checkout_reservation_items ri
  join public.orders o on o.id = ri.order_id
  join public.cart_items ci on ci.id = ri.cart_item_id
  where o.idempotency_key = 'reservation-test-key-001'
    and ri.quantity = 2 and ri.state = 'active'),
  1, 'reservation item records the exact source cart line and quantity');
select is((select used_count from public.offers where code = 'RESERVE10'),
  1, 'offer quota is reserved once');
select is((select count(*)::integer from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-001'),
  1, 'the offer redemption remains in the active accounting ledger');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.checkout_place_order(null, 'reservation-test-key-002')$$,
  'P0001', 'CHECKOUT_QUANTITY_ALREADY_RESERVED',
  'a different idempotency key cannot reserve the same cart quantity');
reset role;
select is((select count(*)::integer from public.orders
  where user_id = '40000000-0000-0000-0000-000000000001'
    and idempotency_key like 'reservation-test-key-%'),
  1, 'conflicting checkout leaves no second order');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'conflicting checkout rolls back its tentative stock decrement');
select is((select used_count from public.offers where code = 'RESERVE10'),
  1, 'conflicting checkout does not consume extra offer quota');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok(
  $$delete from public.cart_items
    where user_id = '40000000-0000-0000-0000-000000000001'$$,
  'deleting a reserved cart row is safely suppressed');
reset role;
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  2, 'reserved cart row remains after a delete request');
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.update_cart_quantity(
    (select id from public.cart_items
      where user_id = '40000000-0000-0000-0000-000000000001'
        and product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
    1)$$,
  'P0001', 'CART_QUANTITY_RESERVED',
  'cart quantity cannot be lowered below the active reservation');
select lives_ok(
  $$select public.update_cart_quantity(
    (select id from public.cart_items
      where user_id = '40000000-0000-0000-0000-000000000001'
        and product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
    3)$$,
  'cart quantity can be increased above the reserved amount');
reset role;
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  3, 'cart update preserves the reserved quantity plus the new unreserved unit');

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select lives_ok(
  $$do $settle$ declare v_order_id uuid; v_claim record; v_result text;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'reservation-test-key-001';
    select * into v_claim from public.claim_razorpay_order(
      v_order_id, '40000000-0000-0000-0000-000000000001');
    perform public.complete_razorpay_order(v_order_id, v_claim.claim_token, 'rzp_reservation_order_001');
    v_result := public.record_verified_razorpay_payment(
      v_order_id, '40000000-0000-0000-0000-000000000001',
      'rzp_reservation_order_001', 'rzp_reservation_payment_001', 3600, 'INR');
    if v_result <> 'captured' then raise exception 'unexpected result: %', v_result; end if;
  end $settle$;$$,
  'verified payment atomically consumes reservation and cart quantity');
reset role;
select is((select status from public.orders
  where idempotency_key = 'reservation-test-key-001'), 'paid',
  'verified payment marks the order paid');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-001'), 'consumed',
  'verified payment consumes the reservation once');
select is((select state from public.checkout_reservation_items ri
  join public.orders o on o.id = ri.order_id
  where o.idempotency_key = 'reservation-test-key-001'), 'consumed',
  'reservation item state follows the parent reservation');
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'payment consumes only the checked-out quantity');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'payment does not decrement the already-reserved stock twice');
select is((select used_count from public.offers where code = 'RESERVE10'),
  1, 'successful payment keeps offer usage consumed');
select is((select count(*)::integer from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-001'),
  1, 'successful payment preserves offer redemption history');
select is(public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'reservation-test-key-001'),
    '40000000-0000-0000-0000-000000000001', 'rzp_reservation_order_001',
    'rzp_reservation_payment_001', 3600, 'INR'),
  'captured', 'duplicate verified payment is idempotent');
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'duplicate verification does not consume the cart twice');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-001'))$$,
  'P0001', 'PAYMENT_ALREADY_CAPTURED',
  'captured orders cannot release stock through buyer cancellation');
reset role;
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'rejected paid cancellation does not restore stock');
select is((select used_count from public.offers where code = 'RESERVE10'),
  1, 'rejected paid cancellation does not release offer quota');
select is((select count(*)::integer from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-001'),
  1, 'rejected paid cancellation preserves its redemption');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.release_checkout_reservation(
    (select id from public.orders where idempotency_key = 'reservation-test-key-001'))$$,
  'P0001', 'NOT_AUTHORIZED',
  'a different buyer cannot release this reservation');
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.checkout_place_order('RELEASE10', 'reservation-test-key-003')$$,
  'a released cart line can be checked out again');
reset role;
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'second pending order preserves its cart row');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  4, 'second pending order reserves stock');
select is((select used_count from public.offers where code = 'RELEASE10'),
  1, 'second offer quota is reserved');

-- Legacy orders cannot infer payment finality from a missing attempt row.
update public.checkout_reservations r
set source = 'legacy'
from public.orders o
where o.id = r.order_id
  and o.idempotency_key = 'reservation-test-key-003';
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-003'))$$,
  'P0001', 'LEGACY_CHECKOUT_REQUIRES_RECONCILIATION',
  'legacy order is not released based only on an absent attempt row');
reset role;
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  4, 'legacy reconciliation blocker preserves reserved stock');
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'legacy reconciliation blocker preserves the current cart');
select is((select used_count from public.offers where code = 'RELEASE10'),
  1, 'legacy reconciliation blocker preserves offer usage');
update public.checkout_reservations r
set source = 'checkout'
from public.orders o
where o.id = r.order_id
  and o.idempotency_key = 'reservation-test-key-003';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-003'))$$,
  'unpaid order without a payment attempt releases safely');
reset role;
select is((select status from public.orders
  where idempotency_key = 'reservation-test-key-003'), 'cancelled',
  'safe cancellation records the order transition');
select is((select count(*)::integer from public.order_status_history h
  join public.orders o on o.id = h.order_id
  where o.idempotency_key = 'reservation-test-key-003'
    and h.new_status = 'cancelled'),
  1, 'safe cancellation preserves the order-status history event');
select is((select payment_status from public.orders
  where idempotency_key = 'reservation-test-key-003'), 'cancelled',
  'safe cancellation records the unpaid payment state');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-003'), 'released',
  'safe cancellation releases the reservation once');
select is((select state from public.checkout_reservation_items ri
  join public.orders o on o.id = ri.order_id
  where o.idempotency_key = 'reservation-test-key-003'), 'released',
  'safe cancellation releases reservation items');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'safe cancellation restores stock exactly once');
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'safe cancellation leaves the cart quantity intact');
select is((select used_count from public.offers where code = 'RELEASE10'),
  0, 'safe cancellation releases offer quota once');
select is((select count(*)::integer from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-003'),
  0, 'released redemption leaves the active offer ledger');
select is((select count(*)::integer from public.offer_redemption_history h
  where h.order_id = (select id from public.orders
    where idempotency_key = 'reservation-test-key-003')
    and h.archive_reason = 'checkout_reservation_released'),
  1, 'released redemption is preserved in history');
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select lives_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-003'))$$,
  'repeated cancellation is an idempotent no-op');
reset role;
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  5, 'repeated cancellation does not restore stock twice');
select is((select count(*)::integer from public.offer_redemption_history h
  where h.order_id = (select id from public.orders
    where idempotency_key = 'reservation-test-key-003')),
  1, 'repeated cancellation does not duplicate offer history');

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select throws_ok(
  $$select * from public.claim_razorpay_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-003'),
    '40000000-0000-0000-0000-000000000001')$$,
  'P0001', 'ORDER_NOT_PAYABLE',
  'a released order cannot create a provider payment attempt');
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$select public.checkout_place_order(null, 'reservation-test-key-004')$$,
  'buyer can create a new pending order after prior release');
reset role;
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'new pending order keeps its cart quantity until payment');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  4, 'new pending order reserves stock');

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select lives_ok(
  $$do $provider_attempt$ declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'reservation-test-key-004';
    select * into v_claim from public.claim_razorpay_order(
      v_order_id, '40000000-0000-0000-0000-000000000001');
    perform public.complete_razorpay_order(v_order_id, v_claim.claim_token, 'rzp_reservation_order_004');
  end $provider_attempt$;$$,
  'provider attempt is persisted before payment can be attempted');
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.cancel_own_order(
    (select id from public.orders where idempotency_key = 'reservation-test-key-004'))$$,
  'P0001', 'PAYMENT_RECONCILIATION_REQUIRED',
  'an order with a payment attempt remains reserved until reconciled');
reset role;
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-004'), 'active',
  'ambiguous payment keeps its reservation active');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  4, 'ambiguous payment does not release inventory');
select is((select quantity from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  1, 'ambiguous payment does not change cart quantity');

set local role service_role;
select lives_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'reservation-test-key-004'),
    '40000000-0000-0000-0000-000000000001', 'rzp_reservation_order_004',
    'rzp_reservation_payment_004', 2000, 'INR')$$,
  'verified capture consumes the previously ambiguous reservation');
reset role;
select is((select status from public.orders
  where idempotency_key = 'reservation-test-key-004'), 'paid',
  'verified capture updates order state');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'reservation-test-key-004'), 'consumed',
  'verified capture consumes the reservation');
select is((select count(*)::integer from public.cart_items ci
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and ci.product_id = (select id from public.products where name = 'reservation-lifecycle-product')),
  0, 'verified capture removes only the checked-out cart quantity');
select is((select stock from public.products where name = 'reservation-lifecycle-product'),
  4, 'verified capture does not alter already-reserved stock');

-- A discount larger than the eligible subtotal must abort the whole checkout,
-- including its order, reservation, stock, cart, quota, and redemption writes.
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '40000000-0000-0000-0000-000000000001',
  'coupon-boundary-product', 10, 10, 10, 2, 'Electronics'
);
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('TOO_LARGE_FLAT', 'flat', 11, 1, 0);
insert into public.cart_items (user_id, product_id, quantity)
select '40000000-0000-0000-0000-000000000001', id, 1
from public.products where name = 'coupon-boundary-product';
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$select public.checkout_place_order('TOO_LARGE_FLAT', 'coupon-boundary-key-001')$$,
  'P0001', 'OFFER_DISCOUNT_EXCEEDS_SUBTOTAL',
  'fixed discount exceeding eligible subtotal is rejected'
);
reset role;
select is((select count(*)::integer from public.orders
  where idempotency_key = 'coupon-boundary-key-001'),
  0, 'excessive discount creates no order');
select is((select stock from public.products where name = 'coupon-boundary-product'),
  2, 'excessive discount rolls back inventory reservation');
select is((select count(*)::integer from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.user_id = '40000000-0000-0000-0000-000000000001'
    and p.name = 'coupon-boundary-product'),
  1, 'excessive discount preserves the cart item');
select is((select used_count from public.offers where code = 'TOO_LARGE_FLAT'),
  0, 'excessive discount does not consume coupon quota');
select is((select count(*)::integer from public.offer_redemptions r
  where r.offer_id = (select id from public.offers where code = 'TOO_LARGE_FLAT')),
  0, 'excessive discount writes no redemption');

select * from finish();
rollback;
