begin;

do $preflight$
begin
  if to_regclass('public.order_payment_integrity_events') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regclass('public.orders') is null
     or to_regprocedure('public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text)') is null then
    raise exception 'MISSING_PAYMENT_REVIEW_PREREQUISITE';
  end if;
end;
$preflight$;

alter table public.order_payment_integrity_events
  drop constraint if exists order_payment_integrity_events_event_type_check;
alter table public.order_payment_integrity_events
  add constraint order_payment_integrity_events_event_type_check
  check (event_type in ('legacy_demo_quarantined', 'legacy_payment_reconciled', 'payment_review'));
alter table public.order_payment_integrity_events
  add column if not exists review_reason text,
  add column if not exists review_outcome text,
  add column if not exists evidence_reference text;

alter table public.order_payment_integrity_events
  add constraint order_payment_integrity_events_review_fields_check
  check (
    (event_type <> 'payment_review')
    or (review_reason is not null and review_reason ~ '^[A-Z][A-Z0-9_]{2,79}$'
        and review_outcome is not null
        and review_outcome in ('capture_confirmed', 'capture_unconfirmed', 'capture_unknown')
        and evidence_reference is not null
        and length(evidence_reference) between 1 and 200)
  );

create unique index if not exists order_payment_integrity_events_review_once_idx
  on public.order_payment_integrity_events
    (order_id, review_reason, review_outcome, evidence_reference)
  where event_type = 'payment_review';

drop function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text);

create function public.record_razorpay_payment_review(
  p_order_id uuid,
  p_buyer_id uuid,
  p_provider_order_id text,
  p_provider_payment_id text,
  p_amount_paise bigint,
  p_currency text,
  p_reason text,
  p_review_outcome text
) returns text
language plpgsql security definer set search_path = '' as $function$
declare
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_evidence_reference text;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_reason is null or p_reason !~ '^[A-Z][A-Z0-9_]{2,79}$' then raise exception 'INVALID_REVIEW_REASON'; end if;
  if p_review_outcome is null or p_review_outcome not in ('capture_confirmed', 'capture_unconfirmed', 'capture_unknown') then
    raise exception 'INVALID_REVIEW_OUTCOME';
  end if;
  if p_provider_order_id is null or length(btrim(p_provider_order_id)) = 0
     or (p_provider_payment_id is not null and length(btrim(p_provider_payment_id)) = 0) then
    raise exception 'INVALID_PROVIDER_IDENTIFIER';
  end if;
  if p_review_outcome = 'capture_confirmed' and p_provider_payment_id is null then
    raise exception 'CAPTURE_EVIDENCE_REQUIRED';
  end if;

  select * into v_order from public.orders o
    where o.id = p_order_id and o.user_id = p_buyer_id for update;
  if not found then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
    where a.order_id = p_order_id for update;
  if not found or v_attempt.buyer_id <> p_buyer_id then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  if v_attempt.provider_order_id is distinct from p_provider_order_id
     or v_order.razorpay_order_id is distinct from p_provider_order_id then raise exception 'PROVIDER_ORDER_MISMATCH'; end if;
  if v_attempt.expected_amount_paise is distinct from p_amount_paise then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
  if v_attempt.currency is distinct from p_currency then raise exception 'PAYMENT_CURRENCY_MISMATCH'; end if;

  v_evidence_reference := coalesce(p_provider_payment_id, p_provider_order_id);
  if exists (
    select 1 from public.order_payment_integrity_events e
    where e.order_id = p_order_id and e.event_type = 'payment_review'
      and e.review_reason = p_reason and e.review_outcome = p_review_outcome
      and e.evidence_reference = v_evidence_reference
  ) then return 'review_required'; end if;

  if p_review_outcome = 'capture_confirmed' then
    if v_attempt.provider_payment_id is not null
       and v_attempt.provider_payment_id is distinct from p_provider_payment_id then
      raise exception 'PAYMENT_ALREADY_ASSOCIATED';
    end if;
    if v_attempt.state = 'captured' then raise exception 'PAYMENT_ALREADY_ASSOCIATED'; end if;
    if v_attempt.state not in ('created', 'reconciliation_required', 'noncaptured', 'captured_review') then
      raise exception 'PAYMENT_ATTEMPT_NOT_VERIFIABLE';
    end if;
    if v_order.status not in ('pending', 'cancelled') then raise exception 'ORDER_NOT_PAYABLE'; end if;
    update public.razorpay_payment_attempts
      set state = 'captured_review', provider_payment_id = p_provider_payment_id,
          captured_at = coalesce(captured_at, clock_timestamp()), updated_at = clock_timestamp()
      where id = v_attempt.id;
    update public.orders set payment_status = 'payment_review' where id = p_order_id;
  else
    -- Inconsistent or incomplete evidence is not capture evidence. Preserve any
    -- existing captured state and never promote the order into fulfillment.
    if v_attempt.state not in ('captured', 'captured_review', 'refund_pending',
       'partially_refunded', 'refunded', 'refund_failed') then
      update public.razorpay_payment_attempts
        set state = 'reconciliation_required', updated_at = clock_timestamp()
        where id = v_attempt.id;
    end if;
  end if;

  insert into public.order_payment_integrity_events (
    order_id, event_type, previous_status, previous_payment_status,
    next_status, next_payment_status, payment_attempt_id, provider_order_id,
    provider_payment_id, amount_paise, currency, evidence_reference,
    review_reason, review_outcome, actor_role, actor_id
  ) values (
    p_order_id, 'payment_review', v_order.status, v_order.payment_status,
    v_order.status,
    case when p_review_outcome = 'capture_confirmed' then 'payment_review' else v_order.payment_status end,
    v_attempt.id, p_provider_order_id, p_provider_payment_id, p_amount_paise,
    p_currency, v_evidence_reference, p_reason, p_review_outcome,
    coalesce(auth.role(), 'service_role'), auth.uid()
  );
  return 'review_required';
end;
$function$;

revoke all on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text,text)
  to service_role;

comment on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text,text) is
  'Service-role-only review recorder. Only capture_confirmed outcomes set captured fields; other review outcomes retain reason and a bounded provider identifier reference without releasing reservations.';

commit;
