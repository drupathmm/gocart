begin;

do $preflight$
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regprocedure('public.has_verified_razorpay_capture(uuid)') is null then
    raise exception 'MISSING_PAYMENT_INTEGRITY_PREREQUISITE';
  end if;
end;
$preflight$;

-- A trusted provider check may prove one capture while showing an incomplete,
-- refunded, or active sibling attempt.  Preserve that fact for review without
-- promoting the order to paid or releasing its reservation.
create or replace function public.record_razorpay_payment_review(
  p_order_id uuid, p_buyer_id uuid, p_provider_order_id text,
  p_provider_payment_id text, p_amount_paise bigint, p_currency text, p_reason text
) returns text language plpgsql security definer set search_path = '' as $function$
declare v_order public.orders%rowtype; v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_reason is null or p_reason !~ '^[A-Z][A-Z0-9_]{2,79}$' then raise exception 'INVALID_REVIEW_REASON'; end if;
  if p_provider_payment_id is null or length(btrim(p_provider_payment_id)) = 0 then raise exception 'INVALID_PROVIDER_PAYMENT'; end if;
  select * into v_order from public.orders o where o.id = p_order_id and o.user_id = p_buyer_id for update;
  if not found then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a where a.order_id = p_order_id for update;
  if not found or v_attempt.buyer_id <> p_buyer_id then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  if v_attempt.provider_order_id is distinct from p_provider_order_id
     or v_order.razorpay_order_id is distinct from p_provider_order_id then raise exception 'PROVIDER_ORDER_MISMATCH'; end if;
  if v_attempt.expected_amount_paise is distinct from p_amount_paise then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
  if v_attempt.currency is distinct from p_currency then raise exception 'PAYMENT_CURRENCY_MISMATCH'; end if;
  if v_attempt.state = 'captured_review' and v_attempt.provider_payment_id = p_provider_payment_id then return 'review_required'; end if;
  if v_attempt.state = 'captured' then raise exception 'PAYMENT_ALREADY_ASSOCIATED'; end if;
  if v_attempt.state not in ('created', 'reconciliation_required', 'noncaptured', 'captured_review') then
    raise exception 'PAYMENT_ATTEMPT_NOT_VERIFIABLE';
  end if;
  if v_attempt.state = 'captured_review' then raise exception 'PAYMENT_ALREADY_ASSOCIATED'; end if;
  if v_order.status not in ('pending', 'cancelled') then raise exception 'ORDER_NOT_PAYABLE'; end if;
  update public.razorpay_payment_attempts set state = 'captured_review',
    provider_payment_id = p_provider_payment_id, captured_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = v_attempt.id;
  update public.orders set payment_status = 'payment_review' where id = p_order_id;
  return 'review_required';
end;
$function$;
revoke all on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text) to service_role;

-- Preserve the existing captured-evidence filters while enforcing lifecycle
-- authorization at the database boundary, not in the Flutter client.
create or replace function public.merchant_sales_analytics()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_merchant_id uuid := auth.uid(); v_role text; v_merchant_status text; v_analytics jsonb;
begin
  if v_merchant_id is null then raise exception 'NOT_AUTHORIZED'; end if;
  select p.role, p.merchant_status into v_role, v_merchant_status from public.profiles p where p.id = v_merchant_id;
  if v_role is distinct from 'merchant' or v_merchant_status is distinct from 'approved' then raise exception 'NOT_AUTHORIZED'; end if;
  with eligible_lines as (
    select o.id order_id, o.status order_status, o.created_at, oi.product_id, oi.product_name, oi.quantity, oi.line_total
    from public.orders o join public.order_items oi on oi.order_id = o.id
    where oi.merchant_id = v_merchant_id and o.payment_status = 'paid' and o.status in ('paid','shipped','delivered')
      and public.has_verified_razorpay_capture(o.id)
      and exists (select 1 from public.razorpay_payment_attempts a where a.order_id=o.id and a.state='captured')
  ), order_totals as (
    select order_id, min(order_status) order_status, min(created_at) created_at,
      sum(line_total)::numeric(12,2) item_sales, sum(quantity)::integer item_quantity
    from eligible_lines group by order_id
  ) select jsonb_build_object(
    'currency','INR','paid_item_sales',coalesce((select sum(item_sales) from order_totals),0),
    'total_orders',(select count(*) from order_totals),'pending_orders',(select count(*) from order_totals where order_status='paid'),
    'completed_orders',(select count(*) from order_totals where order_status='delivered'),
    'sales_trend',coalesce((select jsonb_agg(jsonb_build_object('date',sale_date,'amount',amount) order by sale_date) from (
      select (created_at at time zone 'UTC')::date sale_date,sum(item_sales)::numeric(12,2) amount from order_totals
      where (created_at at time zone 'UTC')::date between ((now() at time zone 'UTC')::date-6) and (now() at time zone 'UTC')::date
      group by (created_at at time zone 'UTC')::date) d),'[]'::jsonb),
    'top_products',coalesce((select jsonb_agg(jsonb_build_object('product_id',product_id,'product_name',product_name,'quantity',quantity,'sales',sales) order by quantity desc,sales desc,product_name) from (
      select product_id,product_name,sum(quantity)::integer quantity,sum(line_total)::numeric(12,2) sales from eligible_lines
      group by product_id,product_name order by sum(quantity) desc,sum(line_total) desc,product_name limit 5) p),'[]'::jsonb),
    'recent_orders',coalesce((select jsonb_agg(jsonb_build_object('order_id',order_id,'status',order_status,'created_at',created_at,'paid_item_sales',item_sales,'item_quantity',item_quantity) order by created_at desc) from (
      select * from order_totals order by created_at desc limit 10) r),'[]'::jsonb)
  ) into v_analytics;
  return v_analytics;
end;
$function$;
revoke all on function public.merchant_sales_analytics() from public, anon, authenticated, service_role;
grant execute on function public.merchant_sales_analytics() to authenticated;

comment on function public.record_razorpay_payment_review(uuid,uuid,text,text,bigint,text,text) is
  'Service-role-only durable review path for verified captures with unresolved provider siblings or refund evidence; it never marks the order paid or releases reservations.';
commit;
