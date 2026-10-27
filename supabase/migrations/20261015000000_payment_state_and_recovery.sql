begin;

-- Durable provider attempt state. One GoCart order has one Razorpay order
-- creation attempt; ambiguous provider outcomes are reconciled by receipt and
-- never blindly retried.
create table public.razorpay_payment_attempts (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete restrict,
  buyer_id uuid not null references public.profiles(id) on delete restrict,
  expected_amount_paise bigint not null check (expected_amount_paise > 0),
  currency text not null check (currency = 'INR'),
  state text not null check (state in (
    'creating', 'reconciliation_required', 'created', 'captured',
    'captured_review', 'refund_pending', 'partially_refunded',
    'refunded', 'refund_failed'
  )),
  claim_token uuid,
  provider_order_id text unique,
  provider_payment_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  captured_at timestamptz,
  check ((state = 'creating' or state = 'reconciliation_required')
         or claim_token is null)
);

create table public.razorpay_refunds (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.razorpay_payment_attempts(id) on delete restrict,
  request_key text not null check (length(btrim(request_key)) between 8 and 128),
  amount_paise bigint not null check (amount_paise > 0),
  state text not null check (state in (
    'requested', 'processing', 'unknown', 'succeeded', 'failed'
  )),
  provider_refund_id text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (attempt_id, request_key)
);

create index razorpay_refunds_attempt_state_idx
  on public.razorpay_refunds (attempt_id, state);

-- Webhook events store only routing/idempotency metadata. The endpoint must
-- verify the raw request body before calling the insert RPC.
create table public.razorpay_webhook_events (
  event_id text primary key check (length(event_id) between 1 and 200),
  event_type text not null,
  provider_entity_id text,
  state text not null default 'received' check (state in (
    'received', 'processing', 'processed', 'reconciliation_required', 'failed'
  )),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error_code text
);

alter table public.razorpay_payment_attempts enable row level security;
alter table public.razorpay_refunds enable row level security;
alter table public.razorpay_webhook_events enable row level security;
revoke all on public.razorpay_payment_attempts,
  public.razorpay_refunds, public.razorpay_webhook_events
  from public, anon, authenticated, service_role;

-- Preserve existing provider-order mappings without assuming a provider
-- payment was captured.
insert into public.razorpay_payment_attempts (
  order_id, buyer_id, expected_amount_paise, currency, state, provider_order_id
)
select o.id, o.user_id, round(o.total_amount * 100)::bigint, 'INR', 'created',
       o.razorpay_order_id
from public.orders o
where o.razorpay_order_id is not null
on conflict (order_id) do nothing;

create or replace function public.claim_razorpay_order(
  p_order_id uuid,
  p_buyer_id uuid
)
returns table (
  claim_state text,
  claim_token uuid,
  provider_order_id text,
  amount_paise bigint,
  currency text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_order
  from public.orders o
  where o.id = p_order_id and o.user_id = p_buyer_id
  for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  insert into public.razorpay_payment_attempts (
    order_id, buyer_id, expected_amount_paise, currency, state, claim_token
  ) values (
    v_order.id, v_order.user_id, round(v_order.total_amount * 100)::bigint,
    'INR', 'creating', gen_random_uuid()
  ) on conflict (order_id) do nothing
  returning * into v_attempt;

  if found then
    return query select 'claimed'::text, v_attempt.claim_token,
      null::text, v_attempt.expected_amount_paise, v_attempt.currency;
    return;
  end if;

  select * into v_attempt
  from public.razorpay_payment_attempts a
  where a.order_id = p_order_id
  for update;

  if v_attempt.buyer_id <> p_buyer_id then raise exception 'NOT_AUTHORIZED'; end if;
  if v_attempt.state = 'created' then
    return query select 'created'::text, null::uuid,
      v_attempt.provider_order_id, v_attempt.expected_amount_paise, v_attempt.currency;
  elsif v_attempt.state in ('creating', 'reconciliation_required') then
    return query select 'reconcile'::text, v_attempt.claim_token,
      v_attempt.provider_order_id, v_attempt.expected_amount_paise, v_attempt.currency;
  else
    raise exception 'ORDER_NOT_PAYABLE';
  end if;
end;
$function$;

create or replace function public.complete_razorpay_order(
  p_order_id uuid,
  p_claim_token uuid,
  p_provider_order_id text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_provider_order_id is null or length(btrim(p_provider_order_id)) = 0 then
    raise exception 'INVALID_PROVIDER_ORDER';
  end if;

  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;

  if v_attempt.state = 'created'
     and v_attempt.provider_order_id = p_provider_order_id then
    return;
  end if;
  if v_attempt.claim_token is distinct from p_claim_token
     or v_attempt.state not in ('creating', 'reconciliation_required') then
    raise exception 'PAYMENT_ORDER_CLAIM_CONFLICT';
  end if;
  if v_order.razorpay_order_id is not null
     and v_order.razorpay_order_id <> p_provider_order_id then
    raise exception 'PAYMENT_ORDER_CONFLICT';
  end if;

  update public.razorpay_payment_attempts
  set provider_order_id = p_provider_order_id,
      state = 'created', claim_token = null, updated_at = now()
  where id = v_attempt.id;
  update public.orders
  set razorpay_order_id = p_provider_order_id, payment_method = 'razorpay'
  where id = p_order_id;
end;
$function$;

create or replace function public.mark_razorpay_order_recovery(
  p_order_id uuid,
  p_claim_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.razorpay_payment_attempts
  set state = 'reconciliation_required', updated_at = now()
  where order_id = p_order_id
    and claim_token = p_claim_token
    and state in ('creating', 'reconciliation_required');
  if not found then raise exception 'PAYMENT_ORDER_CLAIM_CONFLICT'; end if;
end;
$function$;

create or replace function public.record_verified_razorpay_payment(
  p_order_id uuid,
  p_buyer_id uuid,
  p_provider_order_id text,
  p_provider_payment_id text,
  p_amount_paise bigint,
  p_currency text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select * into v_order from public.orders o
  where o.id = p_order_id and o.user_id = p_buyer_id for update;
  if not found then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found or v_attempt.buyer_id <> p_buyer_id then
    raise exception 'PAYMENT_ATTEMPT_NOT_FOUND';
  end if;
  if v_attempt.provider_order_id is distinct from p_provider_order_id
     or v_order.razorpay_order_id is distinct from p_provider_order_id then
    raise exception 'PROVIDER_ORDER_MISMATCH';
  end if;
  if v_attempt.expected_amount_paise is distinct from p_amount_paise then
    raise exception 'PAYMENT_AMOUNT_MISMATCH';
  end if;
  if v_attempt.currency is distinct from p_currency then
    raise exception 'PAYMENT_CURRENCY_MISMATCH';
  end if;
  if p_provider_payment_id is null or length(btrim(p_provider_payment_id)) = 0 then
    raise exception 'INVALID_PROVIDER_PAYMENT';
  end if;

  if v_attempt.state = 'captured'
     and v_attempt.provider_payment_id = p_provider_payment_id then
    return 'captured';
  end if;
  if v_attempt.state = 'captured' then raise exception 'PAYMENT_ALREADY_ASSOCIATED'; end if;
  if v_attempt.state not in ('created', 'reconciliation_required') then
    raise exception 'PAYMENT_ATTEMPT_NOT_VERIFIABLE';
  end if;

  if v_order.status = 'cancelled' then
    update public.razorpay_payment_attempts
    set state = 'captured_review', provider_payment_id = p_provider_payment_id,
        captured_at = now(), updated_at = now()
    where id = v_attempt.id;
    update public.orders set payment_status = 'payment_review' where id = p_order_id;
    return 'review_required';
  end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  perform public.change_order_status(p_order_id, 'paid');
  update public.razorpay_payment_attempts
  set state = 'captured', provider_payment_id = p_provider_payment_id,
      captured_at = now(), updated_at = now()
  where id = v_attempt.id;
  return 'captured';
end;
$function$;

create or replace function public.request_razorpay_refund(
  p_order_id uuid,
  p_request_key text,
  p_amount_paise bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_reserved bigint;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found or v_attempt.state not in ('captured', 'refund_pending', 'partially_refunded', 'refund_failed') then
    raise exception 'PAYMENT_NOT_CAPTURED';
  end if;
  if v_order.status <> 'cancelled' then raise exception 'ORDER_NOT_CANCELLED'; end if;
  if p_request_key is null or length(btrim(p_request_key)) < 8
     or length(btrim(p_request_key)) > 128 or p_amount_paise is null or p_amount_paise <= 0 then
    raise exception 'INVALID_REFUND_REQUEST';
  end if;

  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = btrim(p_request_key);
  if found then
    if v_refund.amount_paise <> p_amount_paise then raise exception 'REFUND_IDEMPOTENCY_CONFLICT'; end if;
    return v_refund.id;
  end if;

  select coalesce(sum(r.amount_paise), 0)::bigint into v_reserved
  from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id
    and r.state in ('requested', 'processing', 'unknown', 'succeeded');
  if v_reserved + p_amount_paise > v_attempt.expected_amount_paise then
    raise exception 'REFUND_AMOUNT_EXCEEDS_CAPTURED';
  end if;

  insert into public.razorpay_refunds (attempt_id, request_key, amount_paise, state)
  values (v_attempt.id, btrim(p_request_key), p_amount_paise, 'requested')
  returning * into v_refund;
  update public.razorpay_payment_attempts
  set state = 'refund_pending', updated_at = now() where id = v_attempt.id;
  update public.orders set payment_status = 'refund_pending' where id = p_order_id;
  return v_refund.id;
end;
$function$;

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
declare
  v_refund public.razorpay_refunds%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_total_succeeded bigint;
  v_pending_count integer;
  v_failed_count integer;
  v_payment_status text;
  v_attempt_state text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  -- Lock in the same order as checkout/payment verification: order then attempt.
  perform 1 from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id and r.request_key = p_request_key for update;
  if not found then raise exception 'REFUND_NOT_FOUND'; end if;

  if p_state not in ('processing', 'unknown', 'succeeded', 'failed') then
    raise exception 'INVALID_REFUND_STATE';
  end if;
  if v_refund.state = 'succeeded' and p_state <> 'succeeded' then
    raise exception 'REFUND_STATE_REGRESSION';
  end if;
  if v_refund.state = 'failed' and p_state <> 'failed' then
    raise exception 'REFUND_STATE_REGRESSION';
  end if;
  if p_state = 'succeeded' and (p_provider_refund_id is null or length(btrim(p_provider_refund_id)) = 0) then
    raise exception 'PROVIDER_REFUND_ID_REQUIRED';
  end if;

  update public.razorpay_refunds
  set state = p_state,
      provider_refund_id = coalesce(p_provider_refund_id, provider_refund_id),
      updated_at = now()
  where id = v_refund.id;

  select coalesce(sum(r.amount_paise) filter (where r.state = 'succeeded'), 0)::bigint,
         count(*) filter (where r.state in ('requested', 'processing', 'unknown'))::integer,
         count(*) filter (where r.state = 'failed')::integer
  into v_total_succeeded, v_pending_count, v_failed_count
  from public.razorpay_refunds r where r.attempt_id = v_attempt.id;

  if v_total_succeeded >= v_attempt.expected_amount_paise then
    v_payment_status := 'refunded'; v_attempt_state := 'refunded';
  elsif v_pending_count > 0 then
    v_payment_status := 'refund_pending'; v_attempt_state := 'refund_pending';
  elsif v_total_succeeded > 0 then
    v_payment_status := 'partially_refunded'; v_attempt_state := 'partially_refunded';
  elsif v_failed_count > 0 then
    v_payment_status := 'refund_failed'; v_attempt_state := 'refund_failed';
  else
    v_payment_status := 'paid'; v_attempt_state := 'captured';
  end if;
  update public.razorpay_payment_attempts
  set state = v_attempt_state, updated_at = now() where id = v_attempt.id;
  update public.orders set payment_status = v_payment_status where id = p_order_id;
end;
$function$;

create or replace function public.record_razorpay_webhook_event(
  p_event_id text,
  p_event_type text,
  p_provider_entity_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_event_id is null or length(p_event_id) not between 1 and 200
     or p_event_type is null or length(p_event_type) = 0 then
    raise exception 'INVALID_WEBHOOK_EVENT';
  end if;
  insert into public.razorpay_webhook_events (event_id, event_type, provider_entity_id)
  values (p_event_id, p_event_type, p_provider_entity_id)
  on conflict (event_id) do nothing;
  return found;
end;
$function$;

-- Cancellation changes fulfillment state. It does not claim a captured
-- payment was cancelled/refunded; only the refund result RPC updates that fact.
create or replace function public.change_order_status(
  p_order_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_current text;
  v_owner uuid;
  v_allowed boolean := false;
  v_is_service boolean := v_role = 'service_role';
begin
  if p_new_status is null then raise exception 'INVALID_TRANSITION'; end if;
  select status, user_id into v_current, v_owner
  from public.orders where id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_current = p_new_status then return; end if;

  v_allowed :=
    (v_current = 'pending' and p_new_status = 'paid')
    or (v_current = 'paid' and p_new_status = 'shipped')
    or (v_current = 'shipped' and p_new_status = 'delivered')
    or (v_current = 'delivered' and p_new_status = 'return_requested')
    or (v_current in ('pending', 'paid') and p_new_status = 'cancelled');
  if not v_allowed then raise exception 'INVALID_TRANSITION'; end if;
  if p_new_status = 'cancelled' then
    if not v_is_service and (v_user is null or v_user <> v_owner) then
      raise exception 'NOT_AUTHORIZED';
    end if;
  elsif not v_is_service then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_new_status = 'cancelled' then
    update public.products p
    set stock = p.stock + oi.quantity, updated_at = now()
    from public.order_items oi
    where oi.order_id = p_order_id and oi.product_id = p.id;
    update public.offers o
    set used_count = greatest(o.used_count - 1, 0)
    from public.offer_redemptions r
    where r.order_id = p_order_id and r.offer_id = o.id;
    delete from public.offer_redemptions where order_id = p_order_id;
  end if;

  update public.orders
  set status = p_new_status,
      payment_status = case when p_new_status = 'paid' then 'paid' else payment_status end,
      payment_method = case when p_new_status = 'paid' then coalesce(payment_method, 'razorpay') else payment_method end
  where id = p_order_id;
end;
$function$;

revoke all on function public.claim_razorpay_order(uuid, uuid) from public, anon, authenticated;
revoke all on function public.complete_razorpay_order(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.mark_razorpay_order_recovery(uuid, uuid) from public, anon, authenticated;
revoke all on function public.record_verified_razorpay_payment(uuid, uuid, text, text, bigint, text) from public, anon, authenticated;
revoke all on function public.request_razorpay_refund(uuid, text, bigint) from public, anon, authenticated;
revoke all on function public.record_razorpay_refund_result(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.record_razorpay_webhook_event(text, text, text) from public, anon, authenticated;
grant execute on function public.claim_razorpay_order(uuid, uuid) to service_role;
grant execute on function public.complete_razorpay_order(uuid, uuid, text) to service_role;
grant execute on function public.mark_razorpay_order_recovery(uuid, uuid) to service_role;
grant execute on function public.record_verified_razorpay_payment(uuid, uuid, text, text, bigint, text) to service_role;
grant execute on function public.request_razorpay_refund(uuid, text, bigint) to service_role;
grant execute on function public.record_razorpay_refund_result(uuid, text, text, text) to service_role;
grant execute on function public.record_razorpay_webhook_event(text, text, text) to service_role;

commit;
