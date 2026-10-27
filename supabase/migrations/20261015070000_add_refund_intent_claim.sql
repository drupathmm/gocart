begin;

-- The receipt is a provider-side reference, not an idempotency key. Existing
-- rows intentionally remain NULL: an old request may already have reached
-- the provider, so a receipt must never be invented for it during upgrade.
alter table public.razorpay_refunds
  add column provider_receipt text;

create unique index razorpay_refunds_attempt_provider_receipt_uidx
  on public.razorpay_refunds (attempt_id, provider_receipt)
  where provider_receipt is not null;

create or replace function public.claim_razorpay_refund_intent(
  p_order_id uuid,
  p_request_key text,
  p_amount_paise bigint
)
returns table (
  refund_id uuid,
  provider_receipt text,
  refund_state text,
  created boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_refund public.razorpay_refunds%rowtype;
  v_reserved bigint;
  v_provider_receipt text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;

  -- Keep the established lock order used by payment/cancellation/refund RPCs.
  select * into v_order from public.orders o
  where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found
     or v_attempt.buyer_id is distinct from v_order.user_id
     or v_attempt.state not in (
       'captured', 'captured_review', 'refund_pending',
       'partially_refunded', 'refunded', 'refund_failed'
     )
     or v_attempt.provider_payment_id is null
     or v_attempt.captured_at is null then
    raise exception 'PAYMENT_NOT_CAPTURED';
  end if;
  if v_order.status <> 'cancelled' then
    raise exception 'ORDER_NOT_CANCELLED';
  end if;
  if p_request_key is null
     or length(btrim(p_request_key)) < 8
     or length(btrim(p_request_key)) > 128
     or p_amount_paise is null
     or p_amount_paise <= 0 then
    raise exception 'INVALID_REFUND_REQUEST';
  end if;

  select * into v_refund from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id
    and r.request_key = btrim(p_request_key)
  for update;
  if found then
    if v_refund.amount_paise <> p_amount_paise then
      raise exception 'REFUND_IDEMPOTENCY_CONFLICT';
    end if;
    if v_refund.provider_receipt is null then
      raise exception 'REFUND_RECEIPT_REQUIRES_RECONCILIATION';
    end if;
    return query select v_refund.id, v_refund.provider_receipt,
      v_refund.state, false;
    return;
  end if;

  -- record_verified_razorpay_payment stores provider_payment_id/captured_at
  -- only after validating provider amount and INR currency against this
  -- expected amount. There is no separate captured-amount column today.
  select coalesce(sum(r.amount_paise), 0)::bigint into v_reserved
  from public.razorpay_refunds r
  where r.attempt_id = v_attempt.id
    and r.state in ('requested', 'processing', 'unknown', 'succeeded');
  if v_reserved + p_amount_paise > v_attempt.expected_amount_paise then
    raise exception 'REFUND_AMOUNT_EXCEEDS_CAPTURED';
  end if;

  -- 4-character prefix + 32 hexadecimal UUID characters (36 total). The
  -- receipt is a stable reference. Provider idempotency is a separate header
  -- contract and must use the stable refund intent ID.
  v_provider_receipt := 'gcr_' || replace(pg_catalog.gen_random_uuid()::text, '-', '');
  insert into public.razorpay_refunds (
    attempt_id, request_key, amount_paise, state, provider_receipt
  ) values (
    v_attempt.id, btrim(p_request_key), p_amount_paise, 'requested',
    v_provider_receipt
  ) returning * into v_refund;

  update public.razorpay_payment_attempts
  set state = 'refund_pending', updated_at = now()
  where id = v_attempt.id;
  update public.orders set payment_status = 'refund_pending'
  where id = p_order_id;

  return query select v_refund.id, v_refund.provider_receipt,
    v_refund.state, true;
end;
$function$;

-- Preserve the old return type and signature while routing it through the
-- single reservation implementation above.
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
  v_claim record;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  select * into v_claim from public.claim_razorpay_refund_intent(
    p_order_id, p_request_key, p_amount_paise
  );
  return v_claim.refund_id;
end;
$function$;

revoke all on function public.claim_razorpay_refund_intent(uuid, text, bigint)
  from public, anon, authenticated;
revoke all on function public.request_razorpay_refund(uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.claim_razorpay_refund_intent(uuid, text, bigint)
  to service_role;
grant execute on function public.request_razorpay_refund(uuid, text, bigint)
  to service_role;

commit;
