begin;

select plan(48);

select ok(to_regclass('public.razorpay_payment_attempts') is not null, 'provider payment attempt ledger exists');
select ok(to_regclass('public.razorpay_refunds') is not null, 'refund state ledger exists');
select ok(to_regclass('public.razorpay_webhook_events') is not null, 'webhook event idempotency ledger exists');
select ok((select relrowsecurity from pg_class where oid = 'public.razorpay_payment_attempts'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.razorpay_refunds'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.razorpay_webhook_events'::regclass),
  'payment, refund, and webhook ledgers use RLS');
select ok(not has_table_privilege('authenticated', 'public.razorpay_payment_attempts', 'SELECT')
  and not has_table_privilege('anon', 'public.razorpay_payment_attempts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.razorpay_refunds', 'INSERT')
  and not has_table_privilege('authenticated', 'public.razorpay_webhook_events', 'INSERT'),
  'ordinary and anonymous clients cannot read or mutate payment ledgers');
select ok(has_table_privilege('service_role', 'public.razorpay_payment_attempts', 'SELECT')
  and not has_table_privilege('service_role', 'public.razorpay_payment_attempts', 'INSERT')
  and not has_table_privilege('service_role', 'public.razorpay_payment_attempts', 'UPDATE')
  and not has_table_privilege('service_role', 'public.razorpay_payment_attempts', 'DELETE'),
  'verification server has read-only access to payment attempts');
select ok(has_function_privilege('service_role', 'public.claim_razorpay_order(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_razorpay_order(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.claim_razorpay_order_with_key(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_razorpay_order_with_key(uuid,uuid,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.complete_razorpay_order_cached(uuid,uuid,text,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.complete_razorpay_order_cached(uuid,uuid,text,text,jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.claim_payment_verification(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.claim_payment_verification(uuid,uuid,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.cache_payment_verification_response(uuid,uuid,text,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.cache_payment_verification_response(uuid,uuid,text,uuid,jsonb)', 'EXECUTE'),
  'provider claims and response caching remain service-only');
select ok(has_function_privilege('service_role',
    'public.claim_razorpay_refund_intent(uuid,text,bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.claim_razorpay_refund_intent(uuid,text,bigint)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.claim_razorpay_refund_intent(uuid,text,bigint)', 'EXECUTE'),
  'refund-intent claims are executable only by service_role');
select ok(not has_function_privilege('authenticated',
  'public.record_verified_razorpay_payment(uuid,uuid,text,text,bigint,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
  'public.record_razorpay_refund_result(uuid,text,text,text)', 'EXECUTE'),
  'ordinary users cannot transition payment or refund state');

select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email) values
  ('20000000-0000-0000-0000-000000000001', 'payment-buyer@example.invalid'),
  ('20000000-0000-0000-0000-000000000002', 'other-buyer@example.invalid');
insert into public.profiles (id, name, email, role) values
  ('20000000-0000-0000-0000-000000000001', 'Payment Buyer', 'ignored@example.invalid', 'user'),
  ('20000000-0000-0000-0000-000000000002', 'Other Buyer', 'ignored@example.invalid', 'user');
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '20000000-0000-0000-0000-000000000001', 'payment-state-fixture', 12, 10, 10, 5, 'Electronics'
);
insert into public.cart_items (user_id, product_id, quantity)
select '20000000-0000-0000-0000-000000000001', id, 1
from public.products where name = 'payment-state-fixture';
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.checkout_place_order(null, 'payment-state-checkout-key');
reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select throws_ok(
  $$select * from public.claim_razorpay_order(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000002')$$,
  'P0001', 'ORDER_NOT_FOUND', 'a different buyer cannot claim this order');
select lives_ok(
  $$do $test$
  declare v_order_id uuid; v_claim record; v_again record;
  begin
    select id into v_order_id from public.orders where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_order_with_key(
      v_order_id, '20000000-0000-0000-0000-000000000001', 'payment-state-provider-key');
    if v_claim.claim_state <> 'claimed' then raise exception 'expected first claim'; end if;
    select * into v_again from public.claim_razorpay_order_with_key(
      v_order_id, '20000000-0000-0000-0000-000000000001', 'payment-state-provider-key');
    if v_again.claim_state <> 'reconcile' then raise exception 'duplicate claim was not fenced'; end if;
    perform public.mark_razorpay_order_recovery(v_order_id, v_claim.claim_token);
    perform public.complete_razorpay_order_cached(
      v_order_id, v_claim.claim_token, 'rzp_order_local_test', 'payment-state-provider-key',
      jsonb_build_object(
        'order_id', v_order_id,
        'razorpay_order_id', 'rzp_order_local_test',
        'razorpay_key_id', 'rzp_test_public_id',
        'amount', v_claim.amount_paise,
        'currency', 'INR'));
    select * into v_again from public.claim_razorpay_order_with_key(
      v_order_id, '20000000-0000-0000-0000-000000000001', 'payment-state-provider-key');
    if v_again.claim_state <> 'cached'
       or v_again.response_payload ->> 'razorpay_order_id' <> 'rzp_order_local_test' then
      raise exception 'duplicate request did not return the original cached payment response';
    end if;
  end $test$;$$,
  'claim fencing and recovery reconcile one provider order and cache its response');
reset role;
set local role service_role;
select lives_ok(
  $$select 1 from public.razorpay_payment_attempts limit 1$$,
  'the service-role database client can read payment attempts for verification'
);
reset role;
select is(
  (select provider_order_id from public.razorpay_payment_attempts a
   join public.orders o on o.id = a.order_id
   where o.idempotency_key = 'payment-state-checkout-key'),
  'rzp_order_local_test', 'reconciled provider order is saved against the GoCart order');

set local role service_role;
select throws_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000001', 'rzp_order_wrong', 'rzp_payment_test', 1000, 'INR')$$,
  'P0001', 'PROVIDER_ORDER_MISMATCH', 'wrong provider order cannot be associated');
select throws_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000001', 'rzp_order_local_test', 'rzp_payment_test', 999, 'INR')$$,
  'P0001', 'PAYMENT_AMOUNT_MISMATCH', 'amount mismatch cannot mark the order paid');
select throws_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000001', 'rzp_order_local_test', 'rzp_payment_test', 1000, 'USD')$$,
  'P0001', 'PAYMENT_CURRENCY_MISMATCH', 'currency mismatch cannot mark the order paid');
select throws_ok(
  $$select public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000002', 'rzp_order_local_test', 'rzp_payment_test', 1000, 'INR')$$,
  'P0001', 'NOT_AUTHORIZED', 'a different buyer cannot record payment for this order');
select is(
  public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000001', 'rzp_order_local_test', 'rzp_payment_test', 1000, 'INR'),
  'captured', 'verified payment is recorded');
select is(
  public.record_verified_razorpay_payment(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    '20000000-0000-0000-0000-000000000001', 'rzp_order_local_test', 'rzp_payment_test', 1000, 'INR'),
  'captured', 'duplicate verification for the same payment is idempotent');
reset role;
select is((select count(*)::int from public.razorpay_payment_attempts where provider_payment_id = 'rzp_payment_test'),
  1, 'the provider payment is associated once');
select is((select payment_status from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'paid', 'verified payment is recorded as paid');

set local role service_role;
select public.change_order_status(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'), 'cancelled');
reset role;
select is((select payment_status from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'paid', 'cancelling a paid order does not imply a refund');

set local role service_role;
select is(public.record_razorpay_webhook_event('evt_local_test_1', 'payment.captured', 'rzp_payment_test'),
  true, 'first verified webhook event is recorded');
select is(public.record_razorpay_webhook_event('evt_local_test_1', 'payment.captured', 'rzp_payment_test'),
  false, 'duplicate webhook event is ignored idempotently');
select public.request_razorpay_refund(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-01', 500);
select is(
  public.request_razorpay_refund(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'), 'refund-request-key-01', 500),
  public.request_razorpay_refund(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'), 'refund-request-key-01', 500),
  'duplicate refund request returns its original record');
select public.record_razorpay_refund_result(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-01', 'processing', null);
reset role;
select is((select state from public.razorpay_refunds where request_key = 'refund-request-key-01'),
  'processing', 'refund remains processing pending provider confirmation');
select is((select payment_status from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund_pending', 'refund request is not represented as completed');
select is((select count(*)::int from public.razorpay_refunds where request_key = 'refund-request-key-01'),
  1, 'refund request is stored once');

set local role service_role;
select public.record_razorpay_refund_result(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-01', 'unknown', null);
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-while-unknown-key', 501)$$,
  'P0001', 'REFUND_AMOUNT_EXCEEDS_CAPTURED',
  'an unknown refund outcome continues to reserve its amount');
reset role;
select is((select state from public.razorpay_refunds where request_key = 'refund-request-key-01'),
  'unknown', 'ambiguous provider outcome remains recorded as unknown');

set local role service_role;
select public.authorize_razorpay_refund_dispatch(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-01', 'local-test-approval');
select lives_ok(
  $$do $test$
  declare v_order_id uuid; v_claim record; v_attempt public.razorpay_payment_attempts%rowtype;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_refund_dispatch(v_order_id, 'refund-request-key-01');
    select * into v_attempt from public.razorpay_payment_attempts where order_id = v_order_id;
    perform public.record_verified_razorpay_refund_result(
      v_order_id, 'refund-request-key-01', v_claim.lease_token, 'processed',
      'rzp_refund_local_1', v_attempt.provider_payment_id, 500, v_attempt.currency,
      v_claim.receipt
    );
  end $test$;$$,
  'provider success is recorded only through the leased validated result contract');
reset role;
select is((select payment_status from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'partially_refunded', 'partial provider confirmation stays distinct from full refund');

set local role service_role;
select public.request_razorpay_refund(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-02', 500);
select public.authorize_razorpay_refund_dispatch(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-request-key-02', 'local-test-approval');
select lives_ok(
  $$do $test$
  declare v_order_id uuid; v_claim record; v_attempt public.razorpay_payment_attempts%rowtype;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_refund_dispatch(v_order_id, 'refund-request-key-02');
    select * into v_attempt from public.razorpay_payment_attempts where order_id = v_order_id;
    perform public.record_verified_razorpay_refund_result(
      v_order_id, 'refund-request-key-02', v_claim.lease_token, 'failed',
      'rzp_refund_local_2', v_attempt.provider_payment_id, 500, v_attempt.currency,
      v_claim.receipt
    );
  end $test$;$$,
  'provider failure is recorded using the same validated leased result contract');
select throws_ok(
  $$select public.request_razorpay_refund(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-request-key-03', 501)$$,
  'P0001', 'REFUND_AMOUNT_EXCEEDS_CAPTURED', 'refund requests cannot exceed the captured amount');
reset role;
select is((select payment_status from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'partially_refunded', 'failed refund does not erase a confirmed partial refund');

select lives_ok(
  $$do $test$
  declare
    v_order_id uuid;
    v_first record;
    v_again record;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'payment-state-checkout-key';
    select * into v_first from public.claim_razorpay_refund_intent(
      v_order_id, 'refund-claim-stable-01', 100
    );
    if not v_first.created or v_first.refund_state <> 'requested'
       or v_first.provider_receipt is null
       or length(v_first.provider_receipt) <> 36
       or left(v_first.provider_receipt, 4) <> 'gcr_' then
      raise exception 'new intent did not return its stable provider receipt';
    end if;
    select * into v_again from public.claim_razorpay_refund_intent(
      v_order_id, 'refund-claim-stable-01', 100
    );
    if v_again.created or v_again.refund_id <> v_first.refund_id
       or v_again.provider_receipt <> v_first.provider_receipt then
      raise exception 'duplicate claim did not return the original intent and receipt';
    end if;
  end $test$;$$,
  'a repeated claim returns the same refund ID and provider receipt');
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-claim-stable-01', 101)$$,
  'P0001', 'REFUND_IDEMPOTENCY_CONFLICT',
  'same request key with a different amount is rejected');

select ok(has_function_privilege('service_role',
    'public.authorize_razorpay_refund_dispatch(uuid,text,text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.claim_razorpay_refund_dispatch(uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.authorize_razorpay_refund_dispatch(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.claim_razorpay_refund_dispatch(uuid,text)', 'EXECUTE'),
  'dispatch authorization and claim RPCs are service-role-only');
select lives_ok(
  $$do $test$
  declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_refund_dispatch(
      v_order_id, 'refund-claim-stable-01');
    if v_claim.claim_state <> 'approval_required' then
      raise exception 'refund dispatch was not held behind explicit approval';
    end if;
  end $test$;$$,
  'provider dispatch remains blocked until an approval reference is persisted');
select public.authorize_razorpay_refund_dispatch(
  (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
  'refund-claim-stable-01', 'local-test-approval');
select lives_ok(
  $$do $test$
  declare v_order_id uuid; v_claim record;
  begin
    select id into v_order_id from public.orders
      where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_refund_dispatch(
      v_order_id, 'refund-claim-stable-01');
    if v_claim.claim_state <> 'claimed' or v_claim.lease_token is null
       or v_claim.idempotency_key <> v_claim.refund_id::text
       or v_claim.known_provider_refund_id is not null then
      raise exception 'dispatch claim did not return its immutable request and lease';
    end if;
  end $test$;$$,
  'approved dispatch returns a lease and the persisted provider request contract');
select throws_ok(
  $$update public.razorpay_refunds set provider_receipt = 'changed-receipt'
    where request_key = 'refund-claim-stable-01'$$,
  'P0001', 'REFUND_PROVIDER_REQUEST_IMMUTABLE',
  'a persisted provider request cannot be mutated');

select lives_ok(
  $$do $test$
  declare v_claim record; v_order_id uuid;
  begin
    select id into v_order_id from public.orders
    where idempotency_key = 'payment-state-checkout-key';
    select * into v_claim from public.claim_razorpay_refund_intent(
      v_order_id, 'refund-claim-partial-02', 400
    );
    if not v_claim.created or v_claim.provider_receipt is null then
      raise exception 'expected partial refund intent';
    end if;
  end $test$;$$,
  'partial refunds can reserve remaining captured value');
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-claim-over-cap-03', 1)$$,
  'P0001', 'REFUND_AMOUNT_EXCEEDS_CAPTURED',
  'cumulative requested, processing, unknown, and succeeded amounts cannot exceed capture');

insert into public.razorpay_refunds (
  attempt_id, request_key, amount_paise, state
)
select a.id, 'refund-legacy-no-receipt', 1, 'failed'
from public.razorpay_payment_attempts a
join public.orders o on o.id = a.order_id
where o.idempotency_key = 'payment-state-checkout-key';
set local role service_role;
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-legacy-no-receipt', 1)$$,
  'P0001', 'REFUND_REQUEST_REQUIRES_RECONCILIATION',
  'legacy receipt-less intents are not assigned a new provider receipt');
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-unauthorized-claim', 1)$$,
  '42501', null,
  'non-service roles cannot execute the privileged claim RPC');
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);

update public.orders set status = 'pending'
where idempotency_key = 'payment-state-checkout-key';
set local role service_role;
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-ineligible-order', 1)$$,
  'P0001', 'ORDER_NOT_CANCELLED', 'refund claims preserve cancelled-order eligibility');
reset role;
update public.orders set status = 'cancelled'
where idempotency_key = 'payment-state-checkout-key';
update public.razorpay_payment_attempts set state = 'created'
where order_id = (select id from public.orders
  where idempotency_key = 'payment-state-checkout-key');
set local role service_role;
select throws_ok(
  $$select * from public.claim_razorpay_refund_intent(
    (select id from public.orders where idempotency_key = 'payment-state-checkout-key'),
    'refund-ineligible-attempt', 1)$$,
  'P0001', 'PAYMENT_NOT_CAPTURED', 'uncaptured attempts cannot reserve a refund');
reset role;
update public.razorpay_payment_attempts set state = 'refund_pending'
where order_id = (select id from public.orders
  where idempotency_key = 'payment-state-checkout-key');

select ok(lower(pg_get_functiondef(
    'public.claim_razorpay_refund_intent(uuid,text,bigint)'::regprocedure
  )) !~ '(https?://|net\.http|dblink|fetch\s*\()',
  'claim RPC contains no provider or network call');

-- This file runs in one SQL session. It does not prove concurrent safety;
-- that requires independent sessions contending for the same attempt lock.

select * from finish();
rollback;
