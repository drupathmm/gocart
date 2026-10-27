begin;

select no_plan();

select ok(has_function_privilege(
  'service_role', 'public.reap_expired_checkout_reservations(integer)', 'EXECUTE'
), 'service role can invoke reservation recovery');
select ok(not has_function_privilege(
  'authenticated', 'public.reap_expired_checkout_reservations(integer)', 'EXECUTE'
), 'authenticated users cannot invoke reservation recovery');
select ok(not has_function_privilege(
  'anon', 'public.reap_expired_checkout_reservations(integer)', 'EXECUTE'
), 'anonymous users cannot invoke reservation recovery');
select ok(not has_function_privilege(
  'service_role',
  'public.record_authoritative_noncapture_and_release(uuid,text,boolean,boolean,boolean,text)',
  'EXECUTE'
), 'service role cannot invoke unsupported automatic noncapture recovery');
select ok(not has_function_privilege(
  'authenticated',
  'public.record_authoritative_noncapture_and_release(uuid,text,boolean,boolean,boolean,text)',
  'EXECUTE'
), 'authenticated users cannot record authoritative noncapture');
select ok(not has_function_privilege(
  'anon',
  'public.record_authoritative_noncapture_and_release(uuid,text,boolean,boolean,boolean,text)',
  'EXECUTE'
), 'anonymous users cannot record authoritative noncapture');

insert into auth.users (id, email) values
  ('50000000-0000-0000-0000-000000000001', 'integrity-buyer@example.invalid'),
  ('50000000-0000-0000-0000-000000000002', 'integrity-merchant@example.invalid');
insert into public.profiles (id, name, email, role, merchant_status) values
  ('50000000-0000-0000-0000-000000000001', 'Integrity Buyer', 'ignored-buyer@example.invalid', 'user', 'approved'),
  ('50000000-0000-0000-0000-000000000002', 'Integrity Merchant', 'ignored-merchant@example.invalid', 'merchant', 'approved');
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '50000000-0000-0000-0000-000000000002',
  'payment-integrity-recovery-product', 20, 20, 20, 20, 'Electronics'
);

-- A legacy demo row can be retained, but it cannot be promoted to paid without
-- a matching, captured provider attempt.
select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.orders (
  user_id, total_amount, status, payment_method, payment_status
) values (
  '50000000-0000-0000-0000-000000000001', 20, 'legacy_demo', 'demo', 'legacy_demo'
);
insert into public.order_items (
  order_id, product_id, merchant_id, product_name, unit_price, quantity, line_total
)
select o.id, p.id, p.merchant_id, p.name, 20, 1, 20
from public.orders o cross join public.products p
where o.user_id = '50000000-0000-0000-0000-000000000001'
  and o.payment_status = 'legacy_demo'
  and p.name = 'payment-integrity-recovery-product';

select ok(not public.has_verified_razorpay_capture(o.id),
  'legacy demo row has no verified capture evidence')
from public.orders o where o.payment_status = 'legacy_demo';
select set_config('request.jwt.claim.role', 'service_role', true);
select throws_ok(
  $$update public.orders set status = 'paid', payment_status = 'paid'
    where payment_status = 'legacy_demo'$$,
  'P0001', 'PAYMENT_REQUIRES_VERIFIED_CAPTURE',
  'demo marker and local order state cannot establish payment capture');

-- The verified path remains valid and creates a paid order from a server-priced
-- checkout. Replaying checkout with the same key returns the cached response.
insert into public.cart_items (user_id, product_id, quantity)
select '50000000-0000-0000-0000-000000000001', id, 2
from public.products where name = 'payment-integrity-recovery-product';
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select is(
  public.checkout_place_order_cached(null, 'integrity-checkout-key-001'),
  public.checkout_place_order_cached(null, 'integrity-checkout-key-001'),
  'checkout retries return the original cached response'
);
select set_config('request.jwt.claim.role', 'service_role', true);
select lives_ok(
  $$do $capture$
  declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'integrity-checkout-key-001';
    select * into v_claim from public.claim_razorpay_order(
      v_order_id, '50000000-0000-0000-0000-000000000001'
    );
    perform public.complete_razorpay_order(
      v_order_id, v_claim.claim_token, 'rzp_integrity_order_001'
    );
    if public.record_verified_razorpay_payment(
      v_order_id, '50000000-0000-0000-0000-000000000001',
      'rzp_integrity_order_001', 'rzp_integrity_payment_001', 4000, 'INR'
    ) <> 'captured' then raise exception 'expected captured result'; end if;
  end $capture$;$$,
  'a verified provider capture still transitions checkout to paid'
);
select is((select status from public.orders
  where idempotency_key = 'integrity-checkout-key-001'), 'paid',
  'verified order retains its paid fulfillment state');
select ok(public.has_verified_razorpay_capture((select id from public.orders
  where idempotency_key = 'integrity-checkout-key-001')),
  'verified capture evidence matches order, amount, currency, and provider IDs');

-- A legacy order with independently matching captured evidence remains
-- reconcilable; the audit event records the provider payment that justified it.
insert into public.orders (
  user_id, total_amount, status, payment_method, payment_status, razorpay_order_id
) values (
  '50000000-0000-0000-0000-000000000001', 12, 'legacy_demo', 'demo',
  'legacy_demo', 'rzp_historical_order_001'
);
insert into public.checkout_reservations (order_id, state, source)
select id, 'active', 'legacy' from public.orders
where razorpay_order_id = 'rzp_historical_order_001';
insert into public.order_items (
  order_id, product_id, merchant_id, product_name, unit_price, quantity, line_total
)
select o.id, p.id, p.merchant_id, p.name, 12, 1, 12
from public.orders o cross join public.products p
where o.razorpay_order_id = 'rzp_historical_order_001'
  and p.name = 'payment-integrity-recovery-product';
insert into public.razorpay_payment_attempts (
  order_id, buyer_id, expected_amount_paise, currency, state,
  provider_order_id, provider_payment_id, captured_at
)
select o.id, o.user_id, 1200, 'INR', 'captured',
       'rzp_historical_order_001', 'rzp_historical_payment_001', clock_timestamp()
from public.orders o where o.razorpay_order_id = 'rzp_historical_order_001';
update public.orders
set status = 'paid', payment_status = 'paid'
where razorpay_order_id = 'rzp_historical_order_001';
select is((select status from public.orders
  where razorpay_order_id = 'rzp_historical_order_001'), 'paid',
  'matching independently captured legacy payment remains valid');
select ok(exists (
  select 1 from public.order_payment_integrity_events e
  where e.order_id = (select id from public.orders
    where razorpay_order_id = 'rzp_historical_order_001')
    and e.event_type = 'legacy_payment_reconciled'
    and e.provider_payment_id = 'rzp_historical_payment_001'
), 'verified legacy payment reconciliation is auditable');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select is(
  (public.merchant_sales_analytics() ->> 'paid_item_sales')::numeric,
  52::numeric,
  'merchant revenue includes verified captures and excludes unverified demo rows'
);

-- A paid checkout consumes its original cart line; seed the next checkout's
-- buyer cart explicitly so subsequent reservation cases are independent.
insert into public.cart_items (user_id, product_id, quantity)
select '50000000-0000-0000-0000-000000000001', p.id, 2
from public.products p
where p.name = 'payment-integrity-recovery-product'
  and not exists (
    select 1 from public.cart_items ci
    where ci.user_id = '50000000-0000-0000-0000-000000000001'
      and ci.product_id = p.id
  );

-- A reservation without a provider attempt expires atomically, restoring stock
-- and coupon capacity once while preserving the successful response cache.
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('INTEGRITY10', 'percent', 10, 5, 0);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.checkout_place_order_cached('INTEGRITY10', 'integrity-expiry-key-001')$$,
  'checkout reserves stock and coupon capacity'
);
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 17,
  'checkout decrements stock once before expiry');
select is((select used_count from public.offers where code = 'INTEGRITY10'), 1,
  'checkout reserves coupon capacity once');
update public.checkout_reservations r
set expires_at = clock_timestamp() - interval '1 minute'
from public.orders o
where o.id = r.order_id and o.idempotency_key = 'integrity-expiry-key-001';
select set_config('request.jwt.claim.role', 'service_role', true);
select is((select released_count from public.reap_expired_checkout_reservations(10)), 1,
  'expired reservation is released by the locked recovery batch');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 18,
  'expiry restores reserved stock exactly once');
select is((select used_count from public.offers where code = 'INTEGRITY10'), 0,
  'expiry restores coupon capacity exactly once');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-expiry-key-001'), 'released',
  'expired reservation is terminal');
select is((select status from public.orders
  where idempotency_key = 'integrity-expiry-key-001'), 'cancelled',
  'expired unpaid order is cancelled atomically');
select is((select released_count from public.reap_expired_checkout_reservations(10)), 0,
  'reprocessing an expired reservation does not release it twice');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 18,
  'a repeated reaper run does not increment stock again');
select is(
  public.checkout_place_order_cached('INTEGRITY10', 'integrity-expiry-key-001') ->> 'order_id',
  (select resource_id::text from public.idempotency_keys
   where idempotency_key = 'integrity-expiry-key-001'),
  'successful checkout response remains available after reservation expiry'
);

-- An expired claim whose provider dispatch marker was never written is safe to
-- abandon. Stock and offer capacity return once, while the checkout response
-- remains cached for retries.
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('INTEGRITYPRE', 'percent', 10, 5, 0);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.checkout_place_order_cached('INTEGRITYPRE', 'integrity-predispatch-checkout-001')$$,
  'checkout creates an expiring reservation for a pre-dispatch attempt'
);
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 16,
  'pre-dispatch checkout reserves stock before recovery');
select is((select used_count from public.offers where code = 'INTEGRITYPRE'), 1,
  'pre-dispatch checkout reserves offer capacity before recovery');
select set_config('request.jwt.claim.role', 'service_role', true);
select lives_ok(
  $$do $predispatch$
  declare v_order_id uuid; v_claim record; v_reaper record;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'integrity-predispatch-checkout-001';
    select * into v_claim from public.claim_razorpay_order_with_key_recoverable(
      v_order_id, '50000000-0000-0000-0000-000000000001',
      'integrity-predispatch-payment-key-001'
    );
    if v_claim.claim_state <> 'claimed' or v_claim.claim_token is null then
      raise exception 'expected a fresh pre-dispatch claim';
    end if;
    update public.razorpay_payment_attempts
    set claim_lease_expires_at = clock_timestamp() - interval '1 second'
    where order_id = v_order_id;
    update public.checkout_reservations
    set expires_at = clock_timestamp() - interval '1 minute'
    where order_id = v_order_id;
    select * into v_reaper from public.reap_expired_checkout_reservations(10);
    if v_reaper.released_count <> 1 or v_reaper.reconciliation_required_count <> 0 then
      raise exception 'expired pre-dispatch reservation was not safely released';
    end if;
  end $predispatch$;$$,
  'reaper releases an expired reservation after a proven pre-dispatch claim'
);
select is((select state from public.razorpay_payment_attempts a
  join public.orders o on o.id = a.order_id
  where o.idempotency_key = 'integrity-predispatch-checkout-001'),
  'abandoned_before_dispatch', 'pre-dispatch attempt is terminally abandoned');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-predispatch-checkout-001'),
  'released', 'pre-dispatch reservation is released');
select is((select status from public.orders
  where idempotency_key = 'integrity-predispatch-checkout-001'),
  'cancelled', 'pre-dispatch order is cancelled with the reservation');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 18,
  'pre-dispatch recovery restores reserved stock');
select is((select used_count from public.offers where code = 'INTEGRITYPRE'), 0,
  'pre-dispatch recovery restores offer capacity');
select is((select released_count from public.reap_expired_checkout_reservations(10)), 0,
  'repeated pre-dispatch recovery does not release twice');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 18,
  'repeated pre-dispatch recovery does not restore stock twice');
select is((select used_count from public.offers where code = 'INTEGRITYPRE'), 0,
  'repeated pre-dispatch recovery does not restore offer capacity twice');

-- Historical attempts backfilled as `created` have a provider order ID but
-- predate dispatch_started_at. That missing timestamp is ambiguous and must
-- not release stock or coupon capacity. The available provider API does not
-- establish a terminal noncapture state, so automated recovery remains disabled.
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('INTEGRITYHIST', 'percent', 10, 5, 0);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.checkout_place_order_cached('INTEGRITYHIST', 'integrity-historical-created-001')$$,
  'historical attempt fixture reserves stock and offer capacity'
);
select set_config('request.jwt.claim.role', 'service_role', true);
select lives_ok(
  $$do $historical_created$
  declare
    v_order_id uuid;
    v_claim record;
    v_reaper record;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'integrity-historical-created-001';

    select * into v_claim from public.claim_razorpay_order_with_key_recoverable(
      v_order_id, '50000000-0000-0000-0000-000000000001',
      'integrity-historical-payment-key-001'
    );
    if v_claim.claim_state <> 'claimed' or v_claim.claim_token is null then
      raise exception 'expected a payment-order claim for the historical fixture';
    end if;

    -- Model the durable state produced by the older migration: provider order
    -- creation is known, but the later dispatch marker did not yet exist.
    update public.razorpay_payment_attempts
    set state = 'created', claim_token = null,
        claim_lease_expires_at = null, dispatch_started_at = null,
        provider_order_id = 'rzp_integrity_historical_order_001'
    where order_id = v_order_id;
    update public.orders
    set razorpay_order_id = 'rzp_integrity_historical_order_001'
    where id = v_order_id;
    update public.checkout_reservations
    set expires_at = clock_timestamp() - interval '1 minute'
    where order_id = v_order_id;

    select * into v_reaper from public.reap_expired_checkout_reservations(10);
    if v_reaper.released_count <> 0
       or v_reaper.reconciliation_required_count <> 1 then
      raise exception 'missing dispatch timestamp was treated as noncapture';
    end if;
    if not exists (
      select 1 from public.checkout_reservations r
      where r.order_id = v_order_id and r.state = 'active'
    ) then
      raise exception 'ambiguous historical reservation was not held';
    end if;
    if (select p.stock from public.products p
        join public.order_items oi on oi.product_id = p.id
        where oi.order_id = v_order_id) <> 16
       or (select o.used_count from public.offers o
           where o.code = 'INTEGRITYHIST') <> 1 then
      raise exception 'ambiguous historical attempt changed reserved capacity';
    end if;
  end $historical_created$;$$,
  'historical created attempt without a dispatch marker remains held'
);
select throws_ok(
  $$select public.record_authoritative_noncapture_and_release(
    (select id from public.orders where idempotency_key = 'integrity-historical-created-001'),
    'rzp_integrity_historical_order_001', true, true, true,
    'local-test-caller-assertions-are-not-evidence'
  )$$,
  'P0001', 'AUTOMATIC_NONCAPTURE_UNSUPPORTED',
  'even caller-supplied complete booleans and a reference cannot establish noncapture'
);
select is((select state from public.razorpay_payment_attempts a
  join public.orders o on o.id = a.order_id
  where o.idempotency_key = 'integrity-historical-created-001'), 'created',
  'failed noncapture reconciliation leaves the historical attempt unchanged');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-historical-created-001'), 'active',
  'failed noncapture reconciliation leaves the reservation active');
select is((select status from public.orders
  where idempotency_key = 'integrity-historical-created-001'), 'pending',
  'failed noncapture reconciliation leaves the order pending');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 16,
  'failed historical reconciliation leaves stock reserved');
select is((select used_count from public.offers where code = 'INTEGRITYHIST'), 1,
  'failed historical reconciliation leaves offer capacity reserved');
select is((select state from public.razorpay_payment_attempts a
  join public.orders o on o.id = a.order_id
  where o.idempotency_key = 'integrity-historical-created-001'), 'created',
  'unsupported automatic noncapture leaves the historical attempt unchanged');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-historical-created-001'), 'active',
  'unsupported automatic noncapture leaves the historical reservation active');
select is((select status from public.orders
  where idempotency_key = 'integrity-historical-created-001'), 'pending',
  'unsupported automatic noncapture leaves the historical order pending');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 16,
  'historical inventory remains reserved pending manual reconciliation');
select is((select used_count from public.offers where code = 'INTEGRITYHIST'), 1,
  'historical offer capacity remains reserved pending manual reconciliation');

-- The old mutable noncapture fields and an arbitrary evidence reference do
-- not satisfy the reservation release guard.
update public.razorpay_payment_attempts a
set state = 'noncaptured', noncapture_verified_at = clock_timestamp(),
    noncapture_evidence_ref = 'test-only-unverified-reference'
from public.orders o
where o.id = a.order_id
  and o.idempotency_key = 'integrity-historical-created-001';
select throws_ok(
  $$select public.release_checkout_reservation(
    (select id from public.orders where idempotency_key = 'integrity-historical-created-001')
  )$$,
  'P0001', 'PAYMENT_RECONCILIATION_REQUIRED',
  'arbitrary noncapture fields cannot release a historical reservation'
);
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 16,
  'rejected noncapture release does not restore stock');
select is((select used_count from public.offers where code = 'INTEGRITYHIST'), 1,
  'rejected noncapture release does not restore offer capacity');
-- Even if a reservation row is externally marked released, mutable historical
-- noncapture fields cannot pass the order cancellation trigger.
update public.checkout_reservations r
set state = 'released', released_at = clock_timestamp()
from public.orders o
where o.id = r.order_id
  and o.idempotency_key = 'integrity-historical-created-001';
select throws_ok(
  $$update public.orders set status = 'cancelled', payment_status = 'cancelled'
    where idempotency_key = 'integrity-historical-created-001'$$,
  'P0001', 'PAYMENT_RECONCILIATION_REQUIRED',
  'cancellation guard rejects a released reservation with unverified noncapture flags'
);
select is((select status from public.orders
  where idempotency_key = 'integrity-historical-created-001'), 'pending',
  'rejected cancellation leaves the ambiguous order pending');
update public.checkout_reservations r
set state = 'active', released_at = null
from public.orders o
where o.id = r.order_id
  and o.idempotency_key = 'integrity-historical-created-001';
update public.razorpay_payment_attempts a
set state = 'created', noncapture_verified_at = null, noncapture_evidence_ref = null
from public.orders o
where o.id = a.order_id
  and o.idempotency_key = 'integrity-historical-created-001';

-- Pre-dispatch claims can be reclaimed after their lease. Once dispatch is
-- marked, retries reconcile and the reaper waits for authoritative evidence.
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('INTEGRITYAMB', 'percent', 10, 5, 0);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.checkout_place_order_cached('INTEGRITYAMB', 'integrity-recovery-checkout-001')$$,
  'a fresh checkout is available for payment-order recovery checks'
);
select set_config('request.jwt.claim.role', 'service_role', true);
select lives_ok(
  $$do $recovery$
  declare
    v_order_id uuid;
    v_first record;
    v_second record;
    v_after_dispatch record;
    v_reaper record;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'integrity-recovery-checkout-001';

    select * into v_first from public.claim_razorpay_order_with_key_recoverable(
      v_order_id, '50000000-0000-0000-0000-000000000001', 'integrity-payment-key-001'
    );
    if v_first.claim_state <> 'claimed' or v_first.claim_token is null then
      raise exception 'expected a fresh pre-dispatch claim';
    end if;

    update public.razorpay_payment_attempts
    set claim_lease_expires_at = clock_timestamp() - interval '1 second'
    where order_id = v_order_id;
    select * into v_second from public.claim_razorpay_order_with_key_recoverable(
      v_order_id, '50000000-0000-0000-0000-000000000001', 'integrity-payment-key-001'
    );
    if v_second.claim_state <> 'claimed'
       or v_second.claim_token is null
       or v_second.claim_token = v_first.claim_token then
      raise exception 'expired pre-dispatch claim was not safely reclaimed';
    end if;

    perform public.mark_razorpay_order_dispatch_started(v_order_id, v_second.claim_token);
    select * into v_after_dispatch from public.claim_razorpay_order_with_key_recoverable(
      v_order_id, '50000000-0000-0000-0000-000000000001', 'integrity-payment-key-001'
    );
    if v_after_dispatch.claim_state <> 'reconcile' then
      raise exception 'post-dispatch claim was incorrectly made reclaimable';
    end if;

    perform public.complete_razorpay_order(
      v_order_id, v_second.claim_token, 'rzp_integrity_order_002'
    );
    update public.checkout_reservations
    set expires_at = clock_timestamp() - interval '1 minute'
    where order_id = v_order_id;
    select * into v_reaper from public.reap_expired_checkout_reservations(10);
    if v_reaper.released_count <> 0 or v_reaper.reconciliation_required_count <> 1 then
      raise exception 'ambiguous post-dispatch reservation was not held for reconciliation';
    end if;
    if not exists (
      select 1 from public.checkout_reservations r
      where r.order_id = v_order_id and r.state = 'active'
    ) then
      raise exception 'ambiguous post-dispatch reservation was not left active';
    end if;
    if not exists (
      select 1 from public.products p
      where p.name = 'payment-integrity-recovery-product' and p.stock = 14
    ) then
      raise exception 'ambiguous post-dispatch payment restored reserved stock';
    end if;
    if (select o.used_count from public.offers o where o.code = 'INTEGRITYAMB') <> 1 then
      raise exception 'ambiguous post-dispatch payment restored offer capacity';
    end if;

  end $recovery$;$$,
  'post-dispatch reservation stays held when provider outcome is ambiguous'
);
select is((select status from public.orders
  where idempotency_key = 'integrity-recovery-checkout-001'), 'pending',
  'ambiguous provider outcome does not cancel the order');
select is((select state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-recovery-checkout-001'), 'active',
  'ambiguous provider outcome leaves the reservation active');
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 14,
  'ambiguous provider outcome does not restore reserved stock');
select is((select used_count from public.offers where code = 'INTEGRITYAMB'), 1,
  'ambiguous provider outcome does not restore offer capacity');
select is((select released_count from public.reap_expired_checkout_reservations(10)), 0,
  'reaper keeps unresolved dispatched reservations held');

-- Force a ledger invariant failure after stock restoration begins. The failed
-- release must roll back stock, reservation, order, and offer changes together.
insert into public.offers (code, discount_type, discount_value, usage_limit, used_count)
values ('INTEGRITYFAIL', 'percent', 10, 5, 0);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.checkout_place_order_cached('INTEGRITYFAIL', 'integrity-failure-checkout-001')$$,
  'rollback fixture reserves stock and coupon capacity'
);
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 12,
  'rollback fixture has reduced stock before the failed release');
select set_config('request.jwt.claim.role', 'service_role', true);
update public.offers set used_count = 0 where code = 'INTEGRITYFAIL';
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.release_checkout_reservation(
    (select id from public.orders where idempotency_key = 'integrity-failure-checkout-001')
  )$$,
  'P0001', 'OFFER_RESERVATION_INVARIANT_FAILED',
  'offer-ledger failure aborts reservation recovery'
);
select is((select stock from public.products
  where name = 'payment-integrity-recovery-product'), 12,
  'failed release leaves stock unchanged');
select is((select r.state from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-failure-checkout-001'), 'active',
  'failed release leaves reservation active');
select is((select status from public.orders
  where idempotency_key = 'integrity-failure-checkout-001'), 'pending',
  'failed release leaves order pending');
select is((select used_count from public.offers where code = 'INTEGRITYFAIL'), 0,
  'failed release leaves offer counter unchanged');
select is((select count(*)::integer from public.offer_redemptions r
  join public.orders o on o.id = r.order_id
  where o.idempotency_key = 'integrity-failure-checkout-001'), 1,
  'failed release retains the offer redemption row');

-- Analytics remains available only to an approved merchant; the check is in
-- the SECURITY DEFINER function, so a Flutter client cannot bypass it.
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '50000000-0000-0000-0000-000000000002', true);
select lives_ok($$select public.merchant_sales_analytics()$$,
  'approved merchant can read captured-payment analytics');
select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set merchant_status = 'pending'
where id = '50000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.merchant_sales_analytics()$$, 'P0001', 'NOT_AUTHORIZED',
  'pending merchant cannot read analytics');
select set_config('request.jwt.claim.role', 'service_role', true);
update public.profiles set merchant_status = 'suspended'
where id = '50000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.merchant_sales_analytics()$$, 'P0001', 'NOT_AUTHORIZED',
  'suspended merchant cannot read analytics');

select * from finish();
rollback;
