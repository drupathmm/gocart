begin;

-- Keep nullable legacy rows readable, but constrain every recorded status to
-- a state used by the checkout and payment state machines.
do $payment_status_preflight$
declare
  v_invalid text[];
begin
  select array_agg(distinct o.payment_status order by o.payment_status)
    into v_invalid
  from public.orders o
  where o.payment_status is not null
    and o.payment_status not in (
      'unpaid', 'paid', 'cancelled', 'payment_review', 'refund_pending',
      'partially_refunded', 'refunded', 'refund_failed'
    );
  if v_invalid is not null then
    raise exception 'INVALID_EXISTING_PAYMENT_STATUS: %', array_to_string(v_invalid, ', ');
  end if;
end;
$payment_status_preflight$;

alter table public.orders
  add constraint orders_payment_status_valid_check
  check (
    payment_status is null
    or payment_status in (
      'unpaid', 'paid', 'cancelled', 'payment_review', 'refund_pending',
      'partially_refunded', 'refunded', 'refund_failed'
    )
  );

comment on constraint orders_payment_status_valid_check on public.orders is
  'Restricts recorded payment states; NULL remains valid for legacy compatibility.';

-- This trigger is the final database boundary for payment confirmation. It
-- protects against service-role table updates as well as generic RPCs.
create or replace function public.enforce_verified_payment_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if (new.status = 'paid' and old.status is distinct from 'paid')
     or (new.payment_status = 'paid' and old.payment_status is distinct from 'paid') then
    select * into v_attempt
    from public.razorpay_payment_attempts a
    where a.order_id = new.id;

    if not found
       or v_attempt.state <> 'captured'
       or v_attempt.provider_payment_id is null
       or v_attempt.provider_order_id is null
       or v_attempt.provider_order_id is distinct from new.razorpay_order_id
       or v_attempt.expected_amount_paise is distinct from round(new.total_amount * 100)::bigint
       or v_attempt.currency <> 'INR'
       or new.status <> 'paid'
       or new.payment_status <> 'paid' then
      raise exception 'PAYMENT_REQUIRES_VERIFIED_CAPTURE';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.enforce_verified_payment_transition()
  from public, anon, authenticated, service_role;

drop trigger if exists orders_require_verified_payment on public.orders;
create trigger orders_require_verified_payment
  before update of status, payment_status on public.orders
  for each row execute function public.enforce_verified_payment_transition();

-- Generic order-status changes may handle fulfillment and cancellation, but
-- may never confirm payment. The verified-payment RPC below performs that
-- transition only after validating provider facts and updating the ledger.
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
  if p_new_status = 'paid' then
    raise exception 'PAYMENT_CONFIRMATION_REQUIRES_VERIFIED_PAYMENT';
  end if;

  select o.status, o.user_id into v_current, v_owner
  from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_current = p_new_status then return; end if;

  v_allowed :=
    (v_current = 'paid' and p_new_status = 'shipped')
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
  set status = p_new_status
  where id = p_order_id;
end;
$function$;

revoke all on function public.change_order_status(uuid, text)
  from public, anon, authenticated;
grant execute on function public.change_order_status(uuid, text) to service_role;

-- Preserve provider validation and cancellation-review behavior while making
-- this RPC the sole payment-confirmation path. Attempt and order updates are
-- atomic in this transaction; the trigger sees the captured attempt first.
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

  update public.razorpay_payment_attempts
  set state = 'captured', provider_payment_id = p_provider_payment_id,
      captured_at = now(), updated_at = now()
  where id = v_attempt.id;
  update public.orders
  set status = 'paid', payment_status = 'paid', payment_method = 'razorpay'
  where id = p_order_id;
  return 'captured';
end;
$function$;

revoke all on function public.record_verified_razorpay_payment(uuid, uuid, text, text, bigint, text)
  from public, anon, authenticated;
grant execute on function public.record_verified_razorpay_payment(uuid, uuid, text, text, bigint, text)
  to service_role;

commit;
