begin;

select plan(12);

select ok(to_regclass('public.razorpay_webhook_events') is not null,
  'webhook delivery ledger exists');
select ok(has_function_privilege('service_role',
  'public.claim_razorpay_webhook_event(text,text,text)', 'EXECUTE')
  and has_function_privilege('service_role',
  'public.finish_razorpay_webhook_event(text,uuid,text,text)', 'EXECUTE'),
  'webhook claim and completion are available to the server role');
select ok(not has_function_privilege('authenticated',
  'public.claim_razorpay_webhook_event(text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
  'public.claim_razorpay_webhook_event(text,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
  'public.finish_razorpay_webhook_event(text,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
  'public.finish_razorpay_webhook_event(text,uuid,text,text)', 'EXECUTE'),
  'ordinary and anonymous clients cannot claim or finish webhook work');
select ok(not has_table_privilege('authenticated', 'public.razorpay_webhook_events', 'SELECT')
  and not has_table_privilege('anon', 'public.razorpay_webhook_events', 'SELECT')
  and not has_table_privilege('service_role', 'public.razorpay_webhook_events', 'SELECT'),
  'event rows are available only through the narrowly scoped RPCs');
select ok(not has_table_privilege('service_role', 'public.razorpay_webhook_events', 'INSERT')
  and not has_table_privilege('service_role', 'public.razorpay_webhook_events', 'UPDATE')
  and not has_table_privilege('service_role', 'public.razorpay_webhook_events', 'DELETE'),
  'service role cannot bypass event claim and lease RPCs');

select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select throws_ok(
  $$select * from public.claim_razorpay_webhook_event('evt_auth_denied', 'payment.captured', 'pay_denied')$$,
  '42501', null, 'authenticated users cannot claim provider events');
select throws_ok(
  $$select public.finish_razorpay_webhook_event('evt_auth_denied', gen_random_uuid(), 'processed', null)$$,
  '42501', null, 'authenticated users cannot complete provider events');
reset role;

select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select throws_ok(
  $$select * from public.claim_razorpay_webhook_event('evt_anon_denied', 'payment.captured', 'pay_denied')$$,
  '42501', null, 'anonymous users cannot claim provider events');
reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select lives_ok($$do $test$
declare
  v_first record;
  v_busy record;
  v_retry record;
  v_done record;
begin
  select * into v_first from public.claim_razorpay_webhook_event(
    'evt_retry_local_1', 'payment.captured', 'pay_retry_local_1');
  if v_first.claim_state <> 'claimed' or v_first.lease_token is null then
    raise exception 'first claim was not granted';
  end if;
  select * into v_busy from public.claim_razorpay_webhook_event(
    'evt_retry_local_1', 'payment.captured', 'pay_retry_local_1');
  if v_busy.claim_state <> 'busy' then raise exception 'active claim was not fenced'; end if;
  perform public.finish_razorpay_webhook_event(
    'evt_retry_local_1', v_first.lease_token, 'reconciliation_required', 'SIMULATED_INTERRUPTION');
  select * into v_retry from public.claim_razorpay_webhook_event(
    'evt_retry_local_1', 'payment.captured', 'pay_retry_local_1');
  if v_retry.claim_state <> 'claimed' or v_retry.lease_token is null then
    raise exception 'reconciliation event was not retriable';
  end if;
  perform public.finish_razorpay_webhook_event(
    'evt_retry_local_1', v_retry.lease_token, 'processed', null);
  select * into v_done from public.claim_razorpay_webhook_event(
    'evt_retry_local_1', 'payment.captured', 'pay_retry_local_1');
  if v_done.claim_state <> 'processed' or v_done.lease_token is not null then
    raise exception 'processed event was not deduplicated';
  end if;
end $test$;$$,
  'event leases fence concurrent work and allow safe retry after interruption');
reset role;
select lives_ok($$do $test$
declare
  v_first record;
  v_conflict record;
  v_quarantined record;
  v_active record;
  v_active_conflict record;
begin
  select * into v_first from public.claim_razorpay_webhook_event(
    'evt_conflict_local_1', 'payment.captured', 'pay_conflict_local_1');
  perform public.finish_razorpay_webhook_event(
    'evt_conflict_local_1', v_first.lease_token, 'processed', null);
  select * into v_conflict from public.claim_razorpay_webhook_event(
    'evt_conflict_local_1', 'payment.failed', 'pay_other');
  if v_conflict.claim_state <> 'conflict' or v_conflict.lease_token is not null then
    raise exception 'conflicting delivery was not quarantined';
  end if;
  if (select state from public.razorpay_webhook_events
      where event_id = 'evt_conflict_local_1') <> 'reconciliation_required'
     or (select conflict_count from public.razorpay_webhook_events
      where event_id = 'evt_conflict_local_1') <> 1 then
    raise exception 'conflict was not durably recorded';
  end if;
  select * into v_quarantined from public.claim_razorpay_webhook_event(
    'evt_conflict_local_1', 'payment.captured', 'pay_conflict_local_1');
  if v_quarantined.claim_state <> 'quarantined' then
    raise exception 'original event resumed without investigation';
  end if;

  select * into v_active from public.claim_razorpay_webhook_event(
    'evt_active_conflict_local_1', 'payment.captured', 'pay_active_conflict_local_1');
  select * into v_active_conflict from public.claim_razorpay_webhook_event(
    'evt_active_conflict_local_1', 'payment.failed', 'pay_other_active');
  if v_active_conflict.claim_state <> 'conflict' then
    raise exception 'conflicting concurrent delivery was not quarantined';
  end if;
  perform public.finish_razorpay_webhook_event(
    'evt_active_conflict_local_1', v_active.lease_token, 'processed', null);
  if (select state from public.razorpay_webhook_events
      where event_id = 'evt_active_conflict_local_1') <> 'reconciliation_required' then
    raise exception 'worker completion erased concurrent conflict quarantine';
  end if;
end $test$;$$,
  'conflicting delivery metadata is durably quarantined from automatic processing');
reset role;

select lives_ok($$do $test$
declare
  v_claim record;
  v_again record;
begin
  select * into v_claim from public.claim_razorpay_webhook_event(
    'malformed:local-test-digest', 'invalid.malformed_payload', null);
  perform public.finish_razorpay_webhook_event(
    'malformed:local-test-digest', v_claim.lease_token, 'failed', 'MALFORMED_SIGNED_BODY');
  select * into v_again from public.claim_razorpay_webhook_event(
    'malformed:local-test-digest', 'invalid.malformed_payload', null);
  if v_again.claim_state <> 'quarantined' or v_again.lease_token is not null then
    raise exception 'terminal invalid delivery was automatically retried';
  end if;
  select * into v_claim from public.claim_razorpay_webhook_event(
    'unsupported:local-test-digest', 'refund.processed', 'pay_local_test');
  perform public.finish_razorpay_webhook_event(
    'unsupported:local-test-digest', v_claim.lease_token, 'failed', 'UNSUPPORTED_EVENT_TYPE');
  select * into v_again from public.claim_razorpay_webhook_event(
    'unsupported:local-test-digest', 'refund.processed', 'pay_local_test');
  if v_again.claim_state <> 'quarantined' then
    raise exception 'unsupported event family was silently marked complete';
  end if;
end $test$;$$,
  'malformed and unsupported signed deliveries remain durably quarantined on replay');

select lives_ok($$do $test$
declare
  v_first record;
  v_reclaimed record;
begin
  select * into v_first from public.claim_razorpay_webhook_event(
    'evt_abandoned_local_1', 'payment.captured', 'pay_abandoned_local_1');
  update public.razorpay_webhook_events
    set lease_expires_at = clock_timestamp() - interval '1 second'
    where event_id = 'evt_abandoned_local_1';
  select * into v_reclaimed from public.claim_razorpay_webhook_event(
    'evt_abandoned_local_1', 'payment.captured', 'pay_abandoned_local_1');
  if v_reclaimed.claim_state <> 'claimed'
     or v_reclaimed.lease_token is null
     or v_reclaimed.lease_token = v_first.lease_token then
    raise exception 'expired lease was not reclaimed with a new fencing token';
  end if;
  begin
    perform public.finish_razorpay_webhook_event(
      'evt_abandoned_local_1', v_first.lease_token, 'processed', null);
    raise exception 'OLD_LEASE_WAS_ACCEPTED';
  exception when others then
    if sqlerrm <> 'WEBHOOK_EVENT_LEASE_CONFLICT' then raise; end if;
  end;
  perform public.finish_razorpay_webhook_event(
    'evt_abandoned_local_1', v_reclaimed.lease_token, 'processed', null);
end $test$;$$,
  'expired processing lease permits recovery after a worker interruption');

select * from finish();
rollback;
