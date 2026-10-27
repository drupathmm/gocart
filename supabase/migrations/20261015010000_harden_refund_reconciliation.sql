begin;

-- A captured payment discovered after order cancellation needs an explicit
-- review/refund path. Creating this refund request does not itself assert that
-- Razorpay issued the refund.
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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found or v_attempt.state not in (
    'captured', 'captured_review', 'refund_pending', 'partially_refunded', 'refund_failed'
  ) then
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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
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
  if v_refund.provider_refund_id is not null
     and p_provider_refund_id is not null
     and v_refund.provider_refund_id <> p_provider_refund_id then
    raise exception 'PROVIDER_REFUND_CONFLICT';
  end if;
  if p_state = 'succeeded'
     and (p_provider_refund_id is null or length(btrim(p_provider_refund_id)) = 0) then
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

commit;
