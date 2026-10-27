begin;

-- Keep the exact provider request snapshot and the provider idempotency
-- header separate from the provider's receipt reference.
alter table public.razorpay_refunds
  add column provider_request_payment_id text,
  add column provider_request_currency text,
  add column provider_request_speed text,
  add column provider_idempotency_key text,
  add column provider_request_locked_at timestamptz,
  add column dispatch_approved_at timestamptz,
  add column dispatch_approval_reference text,
  add column dispatch_lease_token uuid,
  add column dispatch_lease_expires_at timestamptz,
  add column dispatch_attempt_count integer not null default 0,
  add column provider_response_status text,
  add column provider_response_amount_paise bigint,
  add column provider_response_currency text,
  add column provider_response_receipt text,
  add column provider_response_recorded_at timestamptz,
  add constraint razorpay_refunds_dispatch_attempt_check
    check (dispatch_attempt_count >= 0),
  add constraint razorpay_refunds_dispatch_lease_check
    check ((dispatch_lease_token is null) = (dispatch_lease_expires_at is null)),
  add constraint razorpay_refunds_provider_status_check
    check (provider_response_status is null or provider_response_status in (
      'pending', 'processed', 'failed'
    ));

create unique index razorpay_refunds_provider_idempotency_uidx
  on public.razorpay_refunds (provider_idempotency_key)
  where provider_idempotency_key is not null;

create table public.razorpay_refund_webhook_reconciliation (
  event_id text primary key references public.razorpay_webhook_events(event_id) on delete restrict,
  event_type text not null,
  provider_refund_id text,
  provider_payment_id text,
  amount_paise bigint,
  currency text,
  receipt text,
  provider_status text,
  reason text not null,
  state text not null default 'open' check (state in ('open', 'resolved')),
  received_at timestamptz not null default now(),
  resolved_at timestamptz
);
alter table public.razorpay_refund_webhook_reconciliation enable row level security;
revoke all on public.razorpay_refund_webhook_reconciliation
  from public, anon, authenticated, service_role;

create or replace function public.guard_razorpay_refund_request_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.provider_request_locked_at is not null and (
    new.provider_request_payment_id is distinct from old.provider_request_payment_id
    or new.amount_paise is distinct from old.amount_paise
    or new.provider_request_currency is distinct from old.provider_request_currency
    or new.provider_request_speed is distinct from old.provider_request_speed
    or new.provider_receipt is distinct from old.provider_receipt
    or new.provider_idempotency_key is distinct from old.provider_idempotency_key
    or new.provider_request_locked_at is distinct from old.provider_request_locked_at
  ) then
    raise exception 'REFUND_PROVIDER_REQUEST_IMMUTABLE';
  end if;
  return new;
end;
$function$;

create trigger razorpay_refunds_request_snapshot_guard
before update on public.razorpay_refunds
for each row execute function public.guard_razorpay_refund_request_snapshot();

-- New claims persist the replayable request atomically. Existing intents with
-- no complete snapshot stay blocked for reconciliation; no key or receipt is
-- fabricated for them.
create or replace function public.claim_razorpay_refund_intent(
  p_order_id uuid,
  p_request_key text,
  p_amount_paise bigint
)
returns table (refund_id uuid, provider_receipt text, refund_state text, created boolean)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_reserved bigint;
  v_refund_id uuid;
  v_receipt text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found or v_attempt.buyer_id is distinct from v_order.user_id
     or v_attempt.state not in ('captured', 'captured_review', 'refund_pending',
       'partially_refunded', 'refunded', 'refund_failed')
     or v_attempt.provider_payment_id is null or v_attempt.captured_at is null then
    raise exception 'PAYMENT_NOT_CAPTURED';
  end if;
  if v_order.status <> 'cancelled' then raise exception 'ORDER_NOT_CANCELLED'; end if;
  if p_request_key is null or length(btrim(p_request_key)) not between 8 and 128
     or p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'INVALID_REFUND_REQUEST';
  end if;

  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key) for update;
  if found then
    if v_refund.amount_paise <> p_amount_paise then
      raise exception 'REFUND_IDEMPOTENCY_CONFLICT';
    end if;
    if v_refund.provider_receipt is null or v_refund.provider_request_locked_at is null
       or v_refund.provider_request_payment_id is null
       or v_refund.provider_request_currency is null
       or v_refund.provider_request_speed is null
       or v_refund.provider_idempotency_key is null then
      raise exception 'REFUND_REQUEST_REQUIRES_RECONCILIATION';
    end if;
    return query select v_refund.id, v_refund.provider_receipt, v_refund.state, false;
    return;
  end if;

  select coalesce(sum(r.amount_paise), 0)::bigint into v_reserved
  from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id
    and r.state in ('requested', 'processing', 'unknown', 'succeeded');
  if v_reserved + p_amount_paise > v_attempt.expected_amount_paise then
    raise exception 'REFUND_AMOUNT_EXCEEDS_CAPTURED';
  end if;

  v_refund_id := pg_catalog.gen_random_uuid();
  v_receipt := 'gcr_' || replace(v_refund_id::text, '-', '');
  insert into public.razorpay_refunds (
    id, attempt_id, request_key, amount_paise, state, provider_receipt,
    provider_request_payment_id, provider_request_currency, provider_request_speed,
    provider_idempotency_key, provider_request_locked_at
  ) values (
    v_refund_id, v_attempt.id, btrim(p_request_key), p_amount_paise, 'requested', v_receipt,
    v_attempt.provider_payment_id, v_attempt.currency, 'normal',
    v_refund_id::text, clock_timestamp()
  ) returning * into v_refund;

  update public.razorpay_payment_attempts
    set state = 'refund_pending', updated_at = now() where id = v_attempt.id;
  update public.orders set payment_status = 'refund_pending' where id = p_order_id;
  return query select v_refund.id, v_refund.provider_receipt, v_refund.state, true;
end;
$function$;

create or replace function public.authorize_razorpay_refund_dispatch(
  p_order_id uuid,
  p_request_key text,
  p_approval_reference text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_approval_reference is null or length(btrim(p_approval_reference)) not between 1 and 200 then
    raise exception 'APPROVAL_REFERENCE_REQUIRED';
  end if;
  perform 1 from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key) for update;
  if not found then raise exception 'REFUND_NOT_FOUND'; end if;
  if v_refund.provider_request_locked_at is null or v_refund.provider_receipt is null
     or v_refund.provider_idempotency_key is null then
    raise exception 'REFUND_REQUEST_REQUIRES_RECONCILIATION';
  end if;
  if v_refund.state not in ('requested', 'processing', 'unknown') then
    raise exception 'REFUND_NOT_DISPATCHABLE';
  end if;
  update public.razorpay_refunds
    set dispatch_approved_at = coalesce(dispatch_approved_at, clock_timestamp()),
        dispatch_approval_reference = coalesce(dispatch_approval_reference, btrim(p_approval_reference))
    where id = v_refund.id;
end;
$function$;

create or replace function public.claim_razorpay_refund_dispatch(
  p_order_id uuid,
  p_request_key text
)
returns table (
  claim_state text, lease_token uuid, refund_id uuid, payment_id text,
  amount_paise bigint, currency text, speed text, receipt text, idempotency_key text,
  known_provider_refund_id text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_token uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key) for update;
  if not found then raise exception 'REFUND_NOT_FOUND'; end if;
  if v_refund.state in ('succeeded', 'failed') then
    return query select 'terminal'::text, null::uuid, v_refund.id,
      v_refund.provider_request_payment_id, v_refund.amount_paise,
      v_refund.provider_request_currency, v_refund.provider_request_speed,
      v_refund.provider_receipt, v_refund.provider_idempotency_key,
      v_refund.provider_refund_id;
    return;
  end if;
  if v_refund.dispatch_approved_at is null then
    return query select 'approval_required'::text, null::uuid, v_refund.id,
      v_refund.provider_request_payment_id, v_refund.amount_paise,
      v_refund.provider_request_currency, v_refund.provider_request_speed,
      v_refund.provider_receipt, v_refund.provider_idempotency_key,
      v_refund.provider_refund_id;
    return;
  end if;
  if v_refund.provider_request_locked_at is null or v_refund.provider_receipt is null
     or v_refund.provider_request_payment_id is null
     or v_refund.provider_request_currency is null or v_refund.provider_request_speed is null
     or v_refund.provider_idempotency_key is null then
    return query select 'reconciliation_required'::text, null::uuid, v_refund.id,
      v_refund.provider_request_payment_id, v_refund.amount_paise,
      v_refund.provider_request_currency, v_refund.provider_request_speed,
      v_refund.provider_receipt, v_refund.provider_idempotency_key,
      v_refund.provider_refund_id;
    return;
  end if;
  if v_refund.dispatch_lease_token is not null
     and v_refund.dispatch_lease_expires_at > clock_timestamp() then
    return query select 'busy'::text, null::uuid, v_refund.id,
      v_refund.provider_request_payment_id, v_refund.amount_paise,
      v_refund.provider_request_currency, v_refund.provider_request_speed,
      v_refund.provider_receipt, v_refund.provider_idempotency_key,
      v_refund.provider_refund_id;
    return;
  end if;
  v_token := pg_catalog.gen_random_uuid();
  update public.razorpay_refunds r
    set state = 'processing', dispatch_lease_token = v_token,
        dispatch_lease_expires_at = clock_timestamp() + interval '2 minutes',
        dispatch_attempt_count = r.dispatch_attempt_count + 1, updated_at = clock_timestamp()
    where r.id = v_refund.id;
  return query select 'claimed'::text, v_token, v_refund.id,
    v_refund.provider_request_payment_id, v_refund.amount_paise,
    v_refund.provider_request_currency, v_refund.provider_request_speed,
    v_refund.provider_receipt, v_refund.provider_idempotency_key,
    v_refund.provider_refund_id;
end;
$function$;

create or replace function public.mark_razorpay_refund_unknown(
  p_order_id uuid,
  p_request_key text,
  p_lease_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  update public.razorpay_refunds r
    set state = 'unknown', dispatch_lease_token = null,
        dispatch_lease_expires_at = null, updated_at = clock_timestamp()
    where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key)
      and r.dispatch_lease_token = p_lease_token
      and r.state not in ('succeeded', 'failed');
  if not found then raise exception 'REFUND_DISPATCH_LEASE_CONFLICT'; end if;
end;
$function$;

create or replace function public.record_razorpay_refund_webhook(
  p_event_id text,
  p_event_type text,
  p_provider_refund_id text,
  p_payment_id text,
  p_amount_paise bigint,
  p_currency text,
  p_receipt text,
  p_provider_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_order_id uuid;
  v_target_state text;
  v_reason text;
  v_total_succeeded bigint;
  v_pending_count integer;
  v_failed_count integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_event_type not in ('refund.created', 'refund.processed', 'refund.failed', 'refund.speed_changed') then
    raise exception 'INVALID_REFUND_WEBHOOK';
  end if;
  if (p_provider_status is not null and p_provider_status not in ('pending', 'processed', 'failed'))
     or (p_provider_refund_id is not null and length(p_provider_refund_id) > 200)
     or (p_payment_id is not null and length(p_payment_id) > 200)
     or (p_currency is not null and length(p_currency) <> 3)
     or (p_receipt is not null and length(p_receipt) > 200) then
    raise exception 'INVALID_REFUND_WEBHOOK';
  end if;
  if (p_event_type = 'refund.processed' and p_provider_status is not null and p_provider_status <> 'processed')
     or (p_event_type = 'refund.failed' and p_provider_status <> 'failed') then
    raise exception 'REFUND_WEBHOOK_EVENT_STATUS_MISMATCH';
  end if;
  if not exists (select 1 from public.razorpay_webhook_events e
    where e.event_id = p_event_id and e.event_type = p_event_type
      and (p_provider_refund_id is null or e.provider_entity_id = p_provider_refund_id)
      and e.state = 'processing') then
    raise exception 'WEBHOOK_EVENT_NOT_CLAIMED';
  end if;

  if p_provider_refund_id is null or p_payment_id is null or p_amount_paise is null
     or p_amount_paise <= 0 or p_currency is null or p_provider_status is null then
    insert into public.razorpay_refund_webhook_reconciliation (
      event_id, event_type, provider_refund_id, provider_payment_id,
      amount_paise, currency, receipt, provider_status, reason
    ) values (
      p_event_id, p_event_type, p_provider_refund_id, p_payment_id,
      p_amount_paise, p_currency, p_receipt, p_provider_status, 'INCOMPLETE_REFUND_EVENT'
    ) on conflict (event_id) do update set reason = excluded.reason, state = 'open';
    return 'reconciliation_required';
  end if;
  if (p_event_type = 'refund.processed' and p_provider_status <> 'processed')
     or (p_event_type = 'refund.failed' and p_provider_status <> 'failed') then
    raise exception 'REFUND_WEBHOOK_EVENT_STATUS_MISMATCH';
  end if;

  select a.order_id into v_order_id from public.razorpay_payment_attempts a
  where a.provider_payment_id = p_payment_id;
  if v_order_id is not null then
    perform 1 from public.orders o where o.id = v_order_id for update;
    select * into v_attempt from public.razorpay_payment_attempts a
      where a.order_id = v_order_id for update;
    select * into v_refund from public.razorpay_refunds r
      where r.attempt_id = v_attempt.id and r.provider_refund_id = p_provider_refund_id
      for update;
    if not found and p_receipt is not null then
      select * into v_refund from public.razorpay_refunds r
        where r.attempt_id = v_attempt.id and r.provider_receipt = p_receipt
        for update;
    end if;
    if found then
      if v_refund.provider_request_payment_id is distinct from p_payment_id
         or v_refund.amount_paise is distinct from p_amount_paise
         or v_refund.provider_request_currency is distinct from p_currency
         or (p_receipt is not null and v_refund.provider_receipt is distinct from p_receipt)
         or (v_refund.provider_refund_id is not null
             and v_refund.provider_refund_id is distinct from p_provider_refund_id) then
        v_reason := 'PROVIDER_REFUND_FIELDS_CONFLICT';
      else
        v_target_state := case p_provider_status when 'pending' then 'processing'
          when 'processed' then 'succeeded' else 'failed' end;
        if (v_refund.state = 'succeeded' and v_target_state <> 'succeeded')
           or (v_refund.state = 'failed' and v_target_state <> 'failed') then
          v_reason := 'REFUND_TERMINAL_STATE_CONFLICT';
        else
          update public.razorpay_refunds r set state = v_target_state,
            provider_refund_id = p_provider_refund_id,
            provider_response_status = p_provider_status,
            provider_response_amount_paise = p_amount_paise,
            provider_response_currency = p_currency,
            provider_response_receipt = p_receipt,
            provider_response_recorded_at = clock_timestamp(),
            dispatch_lease_token = null, dispatch_lease_expires_at = null,
            updated_at = clock_timestamp()
            where r.id = v_refund.id;
          select coalesce(sum(r.amount_paise) filter (where r.state = 'succeeded'), 0)::bigint,
            count(*) filter (where r.state in ('requested', 'processing', 'unknown'))::integer,
            count(*) filter (where r.state = 'failed')::integer
            into v_total_succeeded, v_pending_count, v_failed_count
            from public.razorpay_refunds r where r.attempt_id = v_attempt.id;
          update public.razorpay_payment_attempts a set state = case
            when v_total_succeeded >= a.expected_amount_paise then 'refunded'
            when v_pending_count > 0 then 'refund_pending'
            when v_total_succeeded > 0 then 'partially_refunded'
            when v_failed_count > 0 then 'refund_failed' else 'captured' end,
            updated_at = clock_timestamp() where a.id = v_attempt.id;
          update public.orders o set payment_status = case
            when v_total_succeeded >= v_attempt.expected_amount_paise then 'refunded'
            when v_pending_count > 0 then 'refund_pending'
            when v_total_succeeded > 0 then 'partially_refunded'
            when v_failed_count > 0 then 'refund_failed' else 'paid' end
            where o.id = v_order_id;
          v_reason := null;
        end if;
      end if;
    else
      v_reason := 'NO_UNAMBIGUOUS_LOCAL_REFUND_MATCH';
    end if;
  else
    v_reason := 'PAYMENT_ATTEMPT_NOT_FOUND';
  end if;

  if v_reason is not null then
    insert into public.razorpay_refund_webhook_reconciliation (
      event_id, event_type, provider_refund_id, provider_payment_id,
      amount_paise, currency, receipt, provider_status, reason
    ) values (
      p_event_id, p_event_type, p_provider_refund_id, p_payment_id,
      p_amount_paise, p_currency, p_receipt, p_provider_status, v_reason
    ) on conflict (event_id) do update set
      reason = excluded.reason, state = 'open';
    return 'reconciliation_required';
  end if;
  return 'recorded';
end;
$function$;

create or replace function public.record_verified_razorpay_refund_result(
  p_order_id uuid,
  p_request_key text,
  p_lease_token uuid,
  p_provider_status text,
  p_provider_refund_id text,
  p_payment_id text,
  p_amount_paise bigint,
  p_currency text,
  p_receipt text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_state text;
  v_total_succeeded bigint;
  v_pending_count integer;
  v_failed_count integer;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  perform 1 from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key) for update;
  if not found then raise exception 'REFUND_NOT_FOUND'; end if;
  if v_refund.dispatch_lease_token is distinct from p_lease_token
     or p_lease_token is null then raise exception 'REFUND_DISPATCH_LEASE_CONFLICT'; end if;
  if p_provider_status not in ('pending', 'processed', 'failed') then
    raise exception 'INVALID_PROVIDER_REFUND_STATUS';
  end if;
  if p_provider_refund_id is null or length(btrim(p_provider_refund_id)) = 0
     or p_payment_id is distinct from v_refund.provider_request_payment_id
     or p_amount_paise is distinct from v_refund.amount_paise
     or p_currency is distinct from v_refund.provider_request_currency
     or (p_receipt is not null and p_receipt is distinct from v_refund.provider_receipt) then
    raise exception 'PROVIDER_REFUND_RESPONSE_MISMATCH';
  end if;
  if v_refund.provider_refund_id is not null
     and v_refund.provider_refund_id is distinct from p_provider_refund_id then
    raise exception 'PROVIDER_REFUND_CONFLICT';
  end if;
  v_state := case p_provider_status when 'pending' then 'processing'
    when 'processed' then 'succeeded' else 'failed' end;
  if (v_refund.state = 'succeeded' and v_state <> 'succeeded')
     or (v_refund.state = 'failed' and v_state <> 'failed') then
    raise exception 'REFUND_STATE_REGRESSION';
  end if;
  update public.razorpay_refunds r
    set state = v_state, provider_refund_id = p_provider_refund_id,
        provider_response_status = p_provider_status,
        provider_response_amount_paise = p_amount_paise,
        provider_response_currency = p_currency,
        provider_response_receipt = p_receipt,
        provider_response_recorded_at = clock_timestamp(),
        dispatch_lease_token = null, dispatch_lease_expires_at = null,
        updated_at = clock_timestamp()
    where r.id = v_refund.id;

  select coalesce(sum(r.amount_paise) filter (where r.state = 'succeeded'), 0)::bigint,
         count(*) filter (where r.state in ('requested', 'processing', 'unknown'))::integer,
         count(*) filter (where r.state = 'failed')::integer
    into v_total_succeeded, v_pending_count, v_failed_count
    from public.razorpay_refunds r where r.attempt_id = v_attempt.id;
  update public.razorpay_payment_attempts a set state = case
    when v_total_succeeded >= a.expected_amount_paise then 'refunded'
    when v_pending_count > 0 then 'refund_pending'
    when v_total_succeeded > 0 then 'partially_refunded'
    when v_failed_count > 0 then 'refund_failed' else 'captured' end,
    updated_at = clock_timestamp() where a.id = v_attempt.id;
  update public.orders o set payment_status = case
    when v_total_succeeded >= v_attempt.expected_amount_paise then 'refunded'
    when v_pending_count > 0 then 'refund_pending'
    when v_total_succeeded > 0 then 'partially_refunded'
    when v_failed_count > 0 then 'refund_failed' else 'paid' end
    where o.id = p_order_id;
end;
$function$;

-- Keep the legacy result RPC for non-terminal progress reports only. Terminal
-- outcomes must use the validated provider-result contract above.
create or replace function public.record_razorpay_refund_result(
  p_order_id uuid,
  p_request_key text,
  p_state text,
  p_provider_refund_id text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_state not in ('processing', 'unknown') then
    raise exception 'VERIFIED_REFUND_RESPONSE_REQUIRED';
  end if;
  update public.razorpay_refunds r
    set state = p_state, updated_at = clock_timestamp()
    from public.razorpay_payment_attempts a
    where a.order_id = p_order_id and r.attempt_id = a.id
      and r.request_key = btrim(p_request_key)
      and r.state not in ('succeeded', 'failed');
  if not found then raise exception 'REFUND_NOT_FOUND_OR_TERMINAL'; end if;
end;
$function$;

revoke all on function public.guard_razorpay_refund_request_snapshot() from public, anon, authenticated;
revoke all on function public.authorize_razorpay_refund_dispatch(uuid, text, text) from public, anon, authenticated;
revoke all on function public.claim_razorpay_refund_dispatch(uuid, text) from public, anon, authenticated;
revoke all on function public.mark_razorpay_refund_unknown(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.record_verified_razorpay_refund_result(uuid, text, uuid, text, text, text, bigint, text, text) from public, anon, authenticated;
revoke all on function public.record_razorpay_refund_webhook(text, text, text, text, bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.authorize_razorpay_refund_dispatch(uuid, text, text) to service_role;
grant execute on function public.claim_razorpay_refund_dispatch(uuid, text) to service_role;
grant execute on function public.mark_razorpay_refund_unknown(uuid, text, uuid) to service_role;
grant execute on function public.record_verified_razorpay_refund_result(uuid, text, uuid, text, text, text, bigint, text, text) to service_role;
grant execute on function public.record_razorpay_refund_webhook(text, text, text, text, bigint, text, text, text) to service_role;

commit;
