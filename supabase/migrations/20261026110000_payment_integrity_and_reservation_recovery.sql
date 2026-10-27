begin;

-- This forward-only correction depends on the payment ledger, verified-payment
-- guard, checkout reservation ledger, and durable idempotency migration.
do $preflight$
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regclass('public.checkout_reservations') is null
     or to_regclass('public.idempotency_keys') is null
     or to_regclass('public.order_status_history') is null
     or to_regprocedure(
       'public.record_verified_razorpay_payment(uuid,uuid,text,text,bigint,text)'
     ) is null
     or to_regprocedure('public.checkout_place_order_cached(text,text)') is null then
    raise exception 'PAYMENT_RECOVERY_PREREQUISITES_MISSING';
  end if;

  -- A demo-marked order with a nonmatching provider attempt may have an
  -- ambiguous payment history. Stop and reconcile it rather than rewriting it.
  if exists (
    select 1
    from public.orders o
    join public.razorpay_payment_attempts a on a.order_id = o.id
    where o.payment_method = 'demo'
      and (
        o.payment_status = 'paid'
        or o.status in ('paid', 'shipped', 'delivered', 'return_requested', 'returned')
      )
      and not (
        a.state in ('captured', 'captured_review', 'refund_pending',
                    'partially_refunded', 'refunded', 'refund_failed')
        and a.provider_payment_id is not null
        and a.provider_order_id is not null
        and a.provider_order_id = o.razorpay_order_id
        and a.expected_amount_paise = round(o.total_amount * 100)::bigint
        and a.currency = 'INR'
        and a.captured_at is not null
      )
  ) then
    raise exception 'DEMO_PAYMENT_ATTEMPT_REQUIRES_RECONCILIATION';
  end if;

  -- Do not guess what happened to non-demo orders that currently look paid but
  -- have no complete captured-payment record. These require owner review first.
  if exists (
    select 1
    from public.orders o
    where o.payment_method is distinct from 'demo'
      and (
        o.payment_status in (
          'paid', 'payment_review', 'refund_pending', 'partially_refunded',
          'refunded', 'refund_failed'
        )
        or o.status in ('paid', 'shipped', 'delivered', 'return_requested', 'returned')
      )
      and not exists (
        select 1
        from public.razorpay_payment_attempts a
        where a.order_id = o.id
          and a.state in ('captured', 'captured_review', 'refund_pending',
                          'partially_refunded', 'refunded', 'refund_failed')
          and a.provider_payment_id is not null
          and a.provider_order_id is not null
          and a.provider_order_id = o.razorpay_order_id
          and a.expected_amount_paise = round(o.total_amount * 100)::bigint
          and a.currency = 'INR'
          and a.captured_at is not null
      )
  ) then
    raise exception 'UNVERIFIED_PAID_ORDER_REQUIRES_RECONCILIATION';
  end if;
end;
$preflight$;

alter table public.orders
  drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check
  check (status in (
    'pending', 'paid', 'shipped', 'cancelled', 'delivered',
    'return_requested', 'returned', 'legacy_demo'
  ));

alter table public.order_status_history
  drop constraint if exists order_status_history_previous_status_check;
alter table public.order_status_history
  add constraint order_status_history_previous_status_check
  check (
    previous_status is null
    or previous_status in (
      'pending', 'paid', 'shipped', 'cancelled', 'delivered',
      'return_requested', 'returned', 'legacy_demo'
    )
  );
alter table public.order_status_history
  drop constraint if exists order_status_history_new_status_check;
alter table public.order_status_history
  add constraint order_status_history_new_status_check
  check (new_status in (
    'pending', 'paid', 'shipped', 'cancelled', 'delivered',
    'return_requested', 'returned', 'legacy_demo'
  ));

alter table public.orders
  drop constraint if exists orders_payment_status_valid_check;
alter table public.orders
  add constraint orders_payment_status_valid_check
  check (
    payment_status is null
    or payment_status in (
      'unpaid', 'paid', 'cancelled', 'payment_review', 'refund_pending',
      'partially_refunded', 'refunded', 'refund_failed', 'legacy_demo'
    )
  );

create table public.order_payment_integrity_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  event_type text not null check (event_type in (
    'legacy_demo_quarantined', 'legacy_payment_reconciled'
  )),
  previous_status text,
  previous_payment_status text,
  previous_payment_method text,
  next_status text,
  next_payment_status text,
  payment_attempt_id uuid references public.razorpay_payment_attempts (id) on delete restrict,
  provider_order_id text,
  provider_payment_id text,
  amount_paise bigint,
  currency text,
  evidence_reference text,
  actor_role text not null,
  actor_id uuid,
  occurred_at timestamptz not null default clock_timestamp()
);

create index order_payment_integrity_events_order_idx
  on public.order_payment_integrity_events (order_id, occurred_at desc);
alter table public.order_payment_integrity_events enable row level security;
revoke all on public.order_payment_integrity_events
  from public, anon, authenticated, service_role;

comment on table public.order_payment_integrity_events is
  'Append-only audit of demo quarantine and later verified-payment reconciliation.';

create or replace function public.has_verified_razorpay_capture(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.orders o
    join public.razorpay_payment_attempts a on a.order_id = o.id
    where o.id = p_order_id
      and a.buyer_id = o.user_id
      and a.state in (
        'captured', 'captured_review', 'refund_pending',
        'partially_refunded', 'refunded', 'refund_failed'
      )
      and a.provider_payment_id is not null
      and a.provider_order_id is not null
      and a.provider_order_id = o.razorpay_order_id
      and a.expected_amount_paise = round(o.total_amount * 100)::bigint
      and a.currency = 'INR'
      and a.captured_at is not null
  );
$function$;
revoke all on function public.has_verified_razorpay_capture(uuid)
  from public, anon, authenticated, service_role;

-- This snapshot records only values observable now. The original pre-2026-10-08
-- values overwritten by that historical migration cannot be reconstructed.
insert into public.order_payment_integrity_events (
  order_id, event_type, previous_status, previous_payment_status,
  previous_payment_method, next_status, next_payment_status,
  evidence_reference, actor_role
)
select o.id, 'legacy_demo_quarantined', o.status, o.payment_status,
       o.payment_method, 'legacy_demo', 'legacy_demo',
       'migration:20261026110000', 'migration'
from public.orders o
where o.payment_method = 'demo'
  and (
    o.payment_status = 'paid'
    or o.status in ('paid', 'shipped', 'delivered', 'return_requested', 'returned')
  )
  and not public.has_verified_razorpay_capture(o.id);

-- The existing order-history trigger records this remediation as a system
-- transition. Scope the service claim to this migration transaction only.
select pg_catalog.set_config('request.jwt.claim.role', 'service_role', true);
update public.orders o
set status = 'legacy_demo', payment_status = 'legacy_demo'
where o.payment_method = 'demo'
  and (
    o.payment_status = 'paid'
    or o.status in ('paid', 'shipped', 'delivered', 'return_requested', 'returned')
  )
  and not public.has_verified_razorpay_capture(o.id);
select pg_catalog.set_config('request.jwt.claim.role', '', true);

-- Guard both direct inserts and future status transitions. A text status alone
-- or a provider order ID alone is never sufficient evidence of capture.
create or replace function public.enforce_verified_payment_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (new.status = 'legacy_demo') is distinct from
     coalesce(new.payment_status = 'legacy_demo', false) then
    raise exception 'LEGACY_DEMO_STATE_MISMATCH';
  end if;
  if new.status = 'paid' and new.payment_status is distinct from 'paid' then
    raise exception 'PAYMENT_STATE_MISMATCH';
  end if;
  if new.payment_status = 'paid'
     and new.status not in ('paid', 'shipped', 'delivered', 'return_requested', 'returned') then
    raise exception 'PAYMENT_STATE_MISMATCH';
  end if;

  if new.payment_status = 'paid' and not exists (
    select 1
    from public.orders o
    join public.razorpay_payment_attempts a on a.order_id = o.id
    where o.id = new.id
      and a.buyer_id = new.user_id
      and a.state = 'captured'
      and a.provider_payment_id is not null
      and a.provider_order_id = new.razorpay_order_id
      and a.expected_amount_paise = round(new.total_amount * 100)::bigint
      and a.currency = 'INR'
      and a.captured_at is not null
  ) then
    raise exception 'PAYMENT_REQUIRES_VERIFIED_CAPTURE';
  end if;

  if new.status in ('paid', 'shipped', 'delivered', 'return_requested', 'returned')
     or new.payment_status in (
       'paid', 'payment_review', 'refund_pending', 'partially_refunded',
       'refunded', 'refund_failed'
     ) then
    if not public.has_verified_razorpay_capture(new.id) then
      raise exception 'PAYMENT_REQUIRES_VERIFIED_CAPTURE';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists orders_require_verified_payment on public.orders;
create trigger orders_require_verified_payment
  before insert or update on public.orders
  for each row execute function public.enforce_verified_payment_transition();

create or replace function public.audit_legacy_payment_reconciliation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if (old.status = 'legacy_demo' or old.payment_status = 'legacy_demo')
     and (new.status = 'paid' or new.payment_status = 'paid') then
    select * into v_attempt
    from public.razorpay_payment_attempts a
    where a.order_id = new.id;
    if not found or not public.has_verified_razorpay_capture(new.id) then
      raise exception 'PAYMENT_REQUIRES_VERIFIED_CAPTURE';
    end if;

    insert into public.order_payment_integrity_events (
      order_id, event_type, previous_status, previous_payment_status,
      previous_payment_method, next_status, next_payment_status,
      payment_attempt_id, provider_order_id, provider_payment_id,
      amount_paise, currency, evidence_reference, actor_role, actor_id
    ) values (
      new.id, 'legacy_payment_reconciled', old.status, old.payment_status,
      old.payment_method, new.status, new.payment_status,
      v_attempt.id, v_attempt.provider_order_id, v_attempt.provider_payment_id,
      v_attempt.expected_amount_paise, v_attempt.currency,
      v_attempt.provider_payment_id, coalesce(auth.role(), 'database'), auth.uid()
    );
  end if;
  return new;
end;
$function$;
revoke all on function public.audit_legacy_payment_reconciliation()
  from public, anon, authenticated, service_role;
create trigger orders_audit_legacy_payment_reconciliation
  after update of status, payment_status on public.orders
  for each row execute function public.audit_legacy_payment_reconciliation();

-- Revenue aggregates require the same provider capture facts as payment state.
create or replace function public.merchant_sales_analytics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_merchant_id uuid := auth.uid();
  v_role text;
  v_analytics jsonb;
begin
  if v_merchant_id is null then raise exception 'NOT_AUTHORIZED'; end if;

  select p.role into v_role
  from public.profiles p
  where p.id = v_merchant_id;
  if v_role is distinct from 'merchant' then raise exception 'NOT_AUTHORIZED'; end if;

  with eligible_lines as (
    select o.id as order_id,
           o.status as order_status,
           o.created_at,
           oi.product_id,
           oi.product_name,
           oi.quantity,
           oi.line_total
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    where oi.merchant_id = v_merchant_id
      and o.payment_status = 'paid'
      and o.status in ('paid', 'shipped', 'delivered')
      and public.has_verified_razorpay_capture(o.id)
      and exists (
        select 1 from public.razorpay_payment_attempts a
        where a.order_id = o.id and a.state = 'captured'
      )
  ), order_totals as (
    select l.order_id,
           min(l.order_status) as order_status,
           min(l.created_at) as created_at,
           sum(l.line_total)::numeric(12, 2) as item_sales,
           sum(l.quantity)::integer as item_quantity
    from eligible_lines l
    group by l.order_id
  )
  select jsonb_build_object(
    'currency', 'INR',
    'paid_item_sales', coalesce((select sum(t.item_sales) from order_totals t), 0),
    'total_orders', (select count(*) from order_totals),
    'pending_orders', (select count(*) from order_totals t where t.order_status = 'paid'),
    'completed_orders', (select count(*) from order_totals t where t.order_status = 'delivered'),
    'sales_trend', coalesce((
      select jsonb_agg(jsonb_build_object('date', d.sale_date, 'amount', d.amount)
                       order by d.sale_date)
      from (
        select (t.created_at at time zone 'UTC')::date as sale_date,
               sum(t.item_sales)::numeric(12, 2) as amount
        from order_totals t
        where (t.created_at at time zone 'UTC')::date between
          ((now() at time zone 'UTC')::date - 6)
          and (now() at time zone 'UTC')::date
        group by (t.created_at at time zone 'UTC')::date
      ) d
    ), '[]'::jsonb),
    'top_products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', p.product_id,
        'product_name', p.product_name,
        'quantity', p.quantity,
        'sales', p.sales
      ) order by p.quantity desc, p.sales desc, p.product_name)
      from (
        select l.product_id,
               l.product_name,
               sum(l.quantity)::integer as quantity,
               sum(l.line_total)::numeric(12, 2) as sales
        from eligible_lines l
        group by l.product_id, l.product_name
        order by sum(l.quantity) desc, sum(l.line_total) desc, l.product_name
        limit 5
      ) p
    ), '[]'::jsonb),
    'recent_orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_id', t.order_id,
        'status', t.order_status,
        'created_at', t.created_at,
        'paid_item_sales', t.item_sales,
        'item_quantity', t.item_quantity
      ) order by t.created_at desc)
      from (
        select * from order_totals
        order by created_at desc
        limit 10
      ) t
    ), '[]'::jsonb)
  ) into v_analytics;

  return v_analytics;
end;
$function$;
revoke all on function public.merchant_sales_analytics()
  from public, anon, authenticated;
grant execute on function public.merchant_sales_analytics() to authenticated;

-- Current checkout reservations get a fixed 15-minute window. Existing
-- checkout-source rows receive a fresh grace period; legacy rows stay unexpired
-- because their historical provider dispatch behavior is not provable.
update public.checkout_reservations
set expires_at = clock_timestamp() + interval '15 minutes'
where state = 'active' and source = 'checkout' and expires_at is null;

create or replace function public.create_checkout_reservation_for_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'pending' and new.payment_status = 'unpaid' then
    insert into public.checkout_reservations (order_id, state, source, expires_at)
    values (new.id, 'active', 'checkout', clock_timestamp() + interval '15 minutes')
    on conflict (order_id) do nothing;
  end if;
  return new;
end;
$function$;

alter table public.razorpay_payment_attempts
  add column dispatch_started_at timestamptz,
  add column claim_lease_expires_at timestamptz,
  add column noncapture_verified_at timestamptz,
  add column noncapture_evidence_ref text;

alter table public.razorpay_payment_attempts
  drop constraint if exists razorpay_payment_attempts_state_check;
alter table public.razorpay_payment_attempts
  add constraint razorpay_payment_attempts_state_check
  check (state in (
    'creating', 'reconciliation_required', 'created', 'captured',
    'captured_review', 'refund_pending', 'partially_refunded',
    'refunded', 'refund_failed', 'abandoned_before_dispatch', 'noncaptured'
  ));
alter table public.razorpay_payment_attempts
  add constraint razorpay_payment_attempts_claim_lease_check
  check (
    claim_lease_expires_at is null
    or (state = 'creating' and claim_token is not null
        and dispatch_started_at is null)
  ),
  add constraint razorpay_payment_attempts_noncapture_evidence_check
  check (
    (state <> 'noncaptured' or noncapture_verified_at is not null)
    and ((noncapture_verified_at is null) = (noncapture_evidence_ref is null))
  ),
  add constraint razorpay_payment_attempts_abandoned_check
  check (
    state <> 'abandoned_before_dispatch'
    or (dispatch_started_at is null and provider_order_id is null
        and provider_payment_id is null and claim_token is null)
  );

-- Claims created before this contract cannot be proven pre-dispatch. Keep them
-- on the conservative reconciliation path rather than making them reclaimable.
update public.razorpay_payment_attempts
set dispatch_started_at = coalesce(dispatch_started_at, created_at),
    claim_lease_expires_at = null
where state in ('creating', 'reconciliation_required')
  and claim_token is not null;

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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_order from public.orders o
  where o.id = p_order_id and o.user_id = p_buyer_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  insert into public.razorpay_payment_attempts (
    order_id, buyer_id, expected_amount_paise, currency, state,
    claim_token, dispatch_started_at
  ) values (
    v_order.id, v_order.user_id, round(v_order.total_amount * 100)::bigint,
    'INR', 'creating', gen_random_uuid(), clock_timestamp()
  ) on conflict (order_id) do nothing
  returning * into v_attempt;

  if found then
    return query select 'claimed'::text, v_attempt.claim_token,
      null::text, v_attempt.expected_amount_paise, v_attempt.currency;
    return;
  end if;

  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_provider_order_id is null or length(btrim(p_provider_order_id)) = 0 then
    raise exception 'INVALID_PROVIDER_ORDER';
  end if;

  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found then raise exception 'PAYMENT_ATTEMPT_NOT_FOUND'; end if;
  if v_attempt.state = 'created'
     and v_attempt.provider_order_id = p_provider_order_id then return; end if;
  if v_attempt.claim_token is distinct from p_claim_token
     or v_attempt.state not in ('creating', 'reconciliation_required') then
    raise exception 'PAYMENT_ORDER_CLAIM_CONFLICT';
  end if;
  if v_attempt.dispatch_started_at is null then
    raise exception 'PAYMENT_ORDER_DISPATCH_NOT_STARTED';
  end if;
  if v_order.razorpay_order_id is not null
     and v_order.razorpay_order_id <> p_provider_order_id then
    raise exception 'PAYMENT_ORDER_CONFLICT';
  end if;

  update public.razorpay_payment_attempts
  set state = 'created', claim_token = null, claim_lease_expires_at = null,
      provider_order_id = p_provider_order_id, updated_at = clock_timestamp()
  where id = v_attempt.id;
  update public.orders set razorpay_order_id = p_provider_order_id where id = p_order_id;
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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  update public.razorpay_payment_attempts
  set state = 'reconciliation_required', claim_lease_expires_at = null,
      updated_at = clock_timestamp()
  where order_id = p_order_id and claim_token = p_claim_token
    and state in ('creating', 'reconciliation_required')
    and dispatch_started_at is not null;
  if not found then raise exception 'PAYMENT_ORDER_CLAIM_CONFLICT'; end if;
end;
$function$;

create or replace function public.mark_razorpay_order_dispatch_started(
  p_order_id uuid,
  p_claim_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  select * into v_order from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  update public.razorpay_payment_attempts a
  set dispatch_started_at = clock_timestamp(), claim_lease_expires_at = null,
      updated_at = clock_timestamp()
  where a.order_id = p_order_id and a.claim_token = p_claim_token
    and a.state = 'creating' and a.dispatch_started_at is null
    and a.claim_lease_expires_at > clock_timestamp();
  if not found then raise exception 'PAYMENT_ORDER_CLAIM_CONFLICT'; end if;
end;
$function$;

-- A late, independently verified capture after a reservation was released is
-- retained for review instead of being discarded or reopening fulfillment.
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
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
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

  if v_attempt.state = 'noncaptured' and v_order.status = 'cancelled' then
    update public.razorpay_payment_attempts
    set state = 'captured_review', provider_payment_id = p_provider_payment_id,
        captured_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = v_attempt.id;
    update public.orders set payment_status = 'payment_review' where id = p_order_id;
    return 'review_required';
  end if;

  if v_attempt.state not in ('created', 'reconciliation_required') then
    raise exception 'PAYMENT_ATTEMPT_NOT_VERIFIABLE';
  end if;
  if v_order.status = 'cancelled' then
    update public.razorpay_payment_attempts
    set state = 'captured_review', provider_payment_id = p_provider_payment_id,
        captured_at = clock_timestamp(), updated_at = clock_timestamp()
    where id = v_attempt.id;
    update public.orders set payment_status = 'payment_review' where id = p_order_id;
    return 'review_required';
  end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  update public.razorpay_payment_attempts
  set state = 'captured', provider_payment_id = p_provider_payment_id,
      captured_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = v_attempt.id;
  update public.orders
  set status = 'paid', payment_status = 'paid', payment_method = 'razorpay'
  where id = p_order_id;
  return 'captured';
end;
$function$;

create or replace function public.claim_razorpay_order_with_key_recoverable(
  p_order_id uuid,
  p_buyer_id uuid,
  p_idempotency_key text
)
returns table (
  claim_state text,
  claim_token uuid,
  provider_order_id text,
  amount_paise bigint,
  currency text,
  response_payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_key_row public.idempotency_keys%rowtype;
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_inserted integer;
  v_token uuid;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  insert into public.idempotency_keys (
    idempotency_key, user_id, operation, resource_id
  ) values (v_key, p_buyer_id, 'razorpay_order', p_order_id)
  on conflict (idempotency_key) do nothing;
  select * into v_key_row from public.idempotency_keys k
  where k.idempotency_key = v_key for update;
  if not found or v_key_row.user_id <> p_buyer_id
     or v_key_row.operation <> 'razorpay_order'
     or v_key_row.resource_id is distinct from p_order_id then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;
  if v_key_row.response_payload is not null then
    return query select 'cached'::text, null::uuid,
      v_key_row.response_payload ->> 'razorpay_order_id',
      (v_key_row.response_payload ->> 'amount')::bigint,
      v_key_row.response_payload ->> 'currency', v_key_row.response_payload;
    return;
  end if;

  select * into v_order from public.orders o
  where o.id = p_order_id and o.user_id = p_buyer_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'ORDER_NOT_PAYABLE';
  end if;

  insert into public.razorpay_payment_attempts (
    order_id, buyer_id, expected_amount_paise, currency, state,
    claim_token, claim_lease_expires_at, create_idempotency_key
  ) values (
    p_order_id, p_buyer_id, round(v_order.total_amount * 100)::bigint,
    'INR', 'creating', gen_random_uuid(),
    clock_timestamp() + interval '2 minutes', v_key
  ) on conflict (order_id) do nothing
  returning * into v_attempt;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select * into v_attempt from public.razorpay_payment_attempts a
    where a.order_id = p_order_id for update;
    if not found or v_attempt.buyer_id <> p_buyer_id then raise exception 'NOT_AUTHORIZED'; end if;

    if v_attempt.create_idempotency_key is null then
      begin
        update public.razorpay_payment_attempts a
        set create_idempotency_key = v_key
        where a.id = v_attempt.id and a.create_idempotency_key is null;
      exception when unique_violation then
        raise exception 'IDEMPOTENCY_CONFLICT';
      end;
      select * into v_attempt from public.razorpay_payment_attempts a
      where a.id = v_attempt.id;
    end if;
    if v_attempt.create_idempotency_key is distinct from v_key then
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;

    if v_attempt.state = 'creating' and v_attempt.dispatch_started_at is null then
      if v_attempt.claim_lease_expires_at is not null
         and v_attempt.claim_lease_expires_at <= clock_timestamp() then
        v_token := gen_random_uuid();
        update public.razorpay_payment_attempts a
        set claim_token = v_token,
            claim_lease_expires_at = clock_timestamp() + interval '2 minutes',
            updated_at = clock_timestamp()
        where a.id = v_attempt.id
        returning * into v_attempt;
        return query select 'claimed'::text, v_attempt.claim_token,
          null::text, v_attempt.expected_amount_paise, v_attempt.currency, null::jsonb;
        return;
      end if;
      return query select 'in_progress'::text, null::uuid,
        null::text, v_attempt.expected_amount_paise, v_attempt.currency, null::jsonb;
      return;
    elsif v_attempt.state in ('creating', 'reconciliation_required') then
      return query select 'reconcile'::text, v_attempt.claim_token,
        v_attempt.provider_order_id, v_attempt.expected_amount_paise,
        v_attempt.currency, null::jsonb;
      return;
    elsif v_attempt.state = 'created' and v_attempt.provider_order_id is not null then
      return query select 'created'::text, null::uuid,
        v_attempt.provider_order_id, v_attempt.expected_amount_paise,
        v_attempt.currency, null::jsonb;
      return;
    else
      raise exception 'ORDER_NOT_PAYABLE';
    end if;
  end if;

  return query select 'claimed'::text, v_attempt.claim_token,
    null::text, v_attempt.expected_amount_paise, v_attempt.currency, null::jsonb;
end;
$function$;

create or replace function public.release_checkout_reservation(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_reservation public.checkout_reservations%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_has_attempt boolean := false;
  v_offer_id uuid;
  v_offer_used_count integer;
  v_line record;
  v_role text := coalesce(auth.role(), '');
  v_user_id uuid := auth.uid();
begin
  select * into v_order from public.orders o
  where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_role <> 'service_role'
     and (v_user_id is null or v_user_id <> v_order.user_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_reservation from public.checkout_reservations r
  where r.order_id = p_order_id for update;
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_FOUND'; end if;
  if v_reservation.state = 'released' and v_order.status = 'cancelled' then return false; end if;
  if v_reservation.state = 'consumed' or v_order.status = 'paid'
     or v_order.payment_status = 'paid' then
    raise exception 'PAYMENT_ALREADY_CAPTURED';
  end if;
  if v_reservation.state <> 'active' or v_order.status <> 'pending'
     or v_order.payment_status <> 'unpaid' then
    raise exception 'CHECKOUT_RESERVATION_NOT_RELEASABLE';
  end if;
  if v_reservation.source = 'legacy' then
    raise exception 'LEGACY_CHECKOUT_REQUIRES_RECONCILIATION';
  end if;

  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  v_has_attempt := found;
  if v_has_attempt then
    if v_attempt.state = 'creating'
       and v_attempt.dispatch_started_at is null
       and v_attempt.claim_lease_expires_at is not null
       and v_attempt.claim_lease_expires_at <= clock_timestamp() then
      update public.razorpay_payment_attempts a
      set state = 'abandoned_before_dispatch', claim_token = null,
          claim_lease_expires_at = null, updated_at = clock_timestamp()
      where a.id = v_attempt.id;
      v_attempt.state := 'abandoned_before_dispatch';
    end if;

    if not (
      (v_attempt.state = 'abandoned_before_dispatch'
       and v_attempt.dispatch_started_at is null
       and v_attempt.provider_order_id is null
       and v_attempt.provider_payment_id is null)
      or (v_attempt.state = 'noncaptured'
          and v_attempt.noncapture_verified_at is not null
          and v_attempt.noncapture_evidence_ref is not null
          and v_attempt.provider_payment_id is null)
    ) then
      raise exception 'PAYMENT_RECONCILIATION_REQUIRED';
    end if;
  end if;

  if not exists (
    select 1 from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
  ) then raise exception 'CHECKOUT_RESERVATION_ITEMS_MISSING'; end if;

  for v_line in
    select p.id
    from public.products p
    join (
      select ri.product_id
      from public.checkout_reservation_items ri
      where ri.order_id = p_order_id and ri.state = 'active'
      group by ri.product_id
    ) reserved on reserved.product_id = p.id
    order by p.id
    for update of p
  loop
    null;
  end loop;

  update public.products p
  set stock = p.stock + reserved.quantity, updated_at = clock_timestamp()
  from (
    select ri.product_id, sum(ri.quantity)::integer as quantity
    from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
    group by ri.product_id
  ) reserved
  where p.id = reserved.product_id;

  select r.offer_id into v_offer_id
  from public.offer_redemptions r where r.order_id = p_order_id for update;
  if found then
    select o.used_count into v_offer_used_count
    from public.offers o where o.id = v_offer_id for update;
    if not found or v_offer_used_count < 1 then
      raise exception 'OFFER_RESERVATION_INVARIANT_FAILED';
    end if;
    update public.offers set used_count = used_count - 1 where id = v_offer_id;
    perform pg_catalog.set_config(
      'gocart.offer_redemption_archive_reason', 'checkout_reservation_released', true
    );
    delete from public.offer_redemptions where order_id = p_order_id;
  end if;

  update public.checkout_reservations
  set state = 'released', released_at = clock_timestamp(), released_by = v_user_id,
      release_reason = case
        when v_role = 'service_role' and v_reservation.expires_at <= clock_timestamp()
          and v_has_attempt and v_attempt.state = 'noncaptured'
          then 'checkout_reservation_expired_after_verified_noncapture'
        when v_role = 'service_role' and v_reservation.expires_at <= clock_timestamp()
          and v_has_attempt then 'checkout_reservation_expired_before_dispatch'
        when v_role = 'service_role' and v_reservation.expires_at <= clock_timestamp()
          then 'checkout_reservation_expired_without_payment_attempt'
        when v_role = 'service_role' then 'service_release_without_payment_attempt'
        else 'buyer_cancelled_without_payment_attempt'
      end
  where order_id = p_order_id and state = 'active';
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_ACTIVE'; end if;

  update public.orders set status = 'cancelled', payment_status = 'cancelled'
  where id = p_order_id;
  return true;
end;
$function$;
revoke all on function public.release_checkout_reservation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.release_checkout_reservation(uuid)
  to authenticated, service_role;

create or replace function public.reap_expired_checkout_reservations(p_batch_size integer default 100)
returns table (released_count integer, reconciliation_required_count integer)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_id uuid;
  v_released integer := 0;
  v_waiting integer := 0;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_batch_size is null or p_batch_size < 1 or p_batch_size > 500 then
    raise exception 'INVALID_RESERVATION_BATCH_SIZE';
  end if;

  for v_order_id in
    select o.id
    from public.orders o
    join public.checkout_reservations r on r.order_id = o.id
    where r.state = 'active' and r.source = 'checkout'
      and r.expires_at <= clock_timestamp()
      and o.status = 'pending' and o.payment_status = 'unpaid'
    order by r.expires_at, r.order_id
    limit p_batch_size
    for update of o skip locked
  loop
    begin
      if public.release_checkout_reservation(v_order_id) then
        v_released := v_released + 1;
      end if;
    exception when raise_exception then
      if sqlerrm = 'PAYMENT_RECONCILIATION_REQUIRED' then
        v_waiting := v_waiting + 1;
      else
        raise;
      end if;
    end;
  end loop;

  return query select v_released, v_waiting;
end;
$function$;
revoke all on function public.reap_expired_checkout_reservations(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.reap_expired_checkout_reservations(integer)
  to service_role;

create or replace function public.record_authoritative_noncapture_and_release(
  p_order_id uuid,
  p_provider_order_id text,
  p_lookup_complete boolean,
  p_no_captured_payment boolean,
  p_provider_order_terminal boolean,
  p_evidence_reference text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_reservation public.checkout_reservations%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
begin
  if auth.role() is distinct from 'service_role' then raise exception 'NOT_AUTHORIZED'; end if;
  if p_lookup_complete is distinct from true
     or p_no_captured_payment is distinct from true
     or p_provider_order_terminal is distinct from true
     or p_evidence_reference is null
     or length(btrim(p_evidence_reference)) < 8
     or length(btrim(p_evidence_reference)) > 256 then
    raise exception 'AUTHORITATIVE_NONCAPTURE_EVIDENCE_REQUIRED';
  end if;

  select * into v_order from public.orders o
  where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status <> 'pending' or v_order.payment_status <> 'unpaid' then
    raise exception 'CHECKOUT_RESERVATION_NOT_RELEASABLE';
  end if;
  select * into v_reservation from public.checkout_reservations r
  where r.order_id = p_order_id for update;
  if not found or v_reservation.state <> 'active'
     or v_reservation.source <> 'checkout'
     or v_reservation.expires_at is null
     or v_reservation.expires_at > clock_timestamp() then
    raise exception 'CHECKOUT_RESERVATION_NOT_EXPIRED';
  end if;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  if not found or v_attempt.state not in ('created', 'reconciliation_required')
     or v_attempt.provider_order_id is null
     or v_attempt.provider_order_id is distinct from p_provider_order_id
     or v_order.razorpay_order_id is distinct from p_provider_order_id
     or v_attempt.provider_payment_id is not null then
    raise exception 'PAYMENT_RECONCILIATION_REQUIRED';
  end if;

  update public.razorpay_payment_attempts
  set state = 'noncaptured', claim_token = null, claim_lease_expires_at = null,
      noncapture_verified_at = clock_timestamp(),
      noncapture_evidence_ref = btrim(p_evidence_reference),
      updated_at = clock_timestamp()
  where id = v_attempt.id;

  if not public.release_checkout_reservation(p_order_id) then return false; end if;
  return true;
end;
$function$;
revoke all on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) to service_role;

revoke all on function public.claim_razorpay_order(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.complete_razorpay_order(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.mark_razorpay_order_recovery(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.mark_razorpay_order_dispatch_started(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_razorpay_order_with_key_recoverable(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_razorpay_order(uuid, uuid) to service_role;
grant execute on function public.complete_razorpay_order(uuid, uuid, text) to service_role;
grant execute on function public.mark_razorpay_order_recovery(uuid, uuid) to service_role;
grant execute on function public.mark_razorpay_order_dispatch_started(uuid, uuid)
  to service_role;
grant execute on function public.claim_razorpay_order_with_key_recoverable(uuid, uuid, text)
  to service_role;

commit;
