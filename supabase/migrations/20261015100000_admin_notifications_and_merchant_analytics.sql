begin;

-- Persist one notification for each merchant registration event. Read state
-- is per administrator so one admin does not consume another admin's alert.
create table if not exists public.admin_merchant_notifications (
  id bigint generated always as identity primary key,
  merchant_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null default 'pending_registration'
    check (event_type = 'pending_registration'),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_status text check (
    resolved_status is null or resolved_status in ('approved', 'suspended')
  ),
  constraint admin_merchant_notifications_event_key
    unique (merchant_id, event_type)
);

create index if not exists admin_merchant_notifications_created_idx
  on public.admin_merchant_notifications (created_at desc);

create table if not exists public.admin_merchant_notification_reads (
  notification_id bigint not null
    references public.admin_merchant_notifications(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id, admin_id)
);

alter table public.admin_merchant_notifications enable row level security;
alter table public.admin_merchant_notification_reads enable row level security;
revoke all privileges on table public.admin_merchant_notifications
  from public, anon, authenticated;
revoke all privileges on table public.admin_merchant_notification_reads
  from public, anon, authenticated;

-- Notification creation and resolution are driven by profile status changes,
-- not by client writes. The unique event key makes retries and repeated
-- profile updates harmless.
create or replace function public.sync_admin_merchant_registration_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.role = 'merchant' and new.merchant_status = 'pending' then
    insert into public.admin_merchant_notifications (merchant_id, event_type)
    values (new.id, 'pending_registration')
    on conflict (merchant_id, event_type) do nothing;
  elsif new.role = 'merchant'
        and new.merchant_status in ('approved', 'suspended') then
    update public.admin_merchant_notifications n
    set resolved_at = coalesce(n.resolved_at, now()),
        resolved_status = new.merchant_status
    where n.merchant_id = new.id
      and n.event_type = 'pending_registration';
  end if;
  return new;
end;
$function$;

revoke all on function public.sync_admin_merchant_registration_notification()
  from public, anon, authenticated;
drop trigger if exists profiles_admin_merchant_notification_insert
  on public.profiles;
drop trigger if exists profiles_admin_merchant_notification_status
  on public.profiles;
create trigger profiles_admin_merchant_notification_insert
  after insert on public.profiles
  for each row execute function public.sync_admin_merchant_registration_notification();
create trigger profiles_admin_merchant_notification_status
  after update of role, merchant_status on public.profiles
  for each row execute function public.sync_admin_merchant_registration_notification();

-- Existing pending requests become visible after this additive migration is
-- installed. A merchant gets at most one notification for this registration.
insert into public.admin_merchant_notifications (merchant_id, event_type)
select p.id, 'pending_registration'
from public.profiles p
where p.role = 'merchant' and p.merchant_status = 'pending'
on conflict (merchant_id, event_type) do nothing;

create or replace function public.admin_list_merchant_notifications()
returns table (
  notification_id bigint,
  merchant_id uuid,
  merchant_name text,
  merchant_email text,
  merchant_created_at timestamptz,
  merchant_status text,
  notification_created_at timestamptz,
  resolved_at timestamptz,
  resolved_status text,
  read_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := auth.uid();
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_admin_id and p.role = 'admin'
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  return query
  select n.id,
         p.id,
         p.name,
         p.email,
         p.created_at,
         p.merchant_status,
         n.created_at,
         n.resolved_at,
         n.resolved_status,
         r.read_at
  from public.admin_merchant_notifications n
  join public.profiles p on p.id = n.merchant_id
  left join public.admin_merchant_notification_reads r
    on r.notification_id = n.id and r.admin_id = v_admin_id
  where n.resolved_at is null
  order by n.created_at desc
  limit 100;
end;
$function$;

create or replace function public.admin_unread_merchant_notification_count()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_count integer;
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_admin_id and p.role = 'admin'
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select count(*)::integer into v_count
  from public.admin_merchant_notifications n
  left join public.admin_merchant_notification_reads r
    on r.notification_id = n.id and r.admin_id = v_admin_id
  where n.resolved_at is null and r.notification_id is null;
  return coalesce(v_count, 0);
end;
$function$;

create or replace function public.admin_mark_merchant_notification_read(
  p_notification_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := auth.uid();
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_admin_id and p.role = 'admin'
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  insert into public.admin_merchant_notification_reads as existing_read (
    notification_id, admin_id, read_at
  )
  select n.id, v_admin_id, now()
  from public.admin_merchant_notifications n
  where n.id = p_notification_id
  on conflict (notification_id, admin_id) do update
  set read_at = coalesce(existing_read.read_at, excluded.read_at);

  if not found then raise exception 'NOTIFICATION_NOT_FOUND'; end if;
end;
$function$;

revoke all on function public.admin_list_merchant_notifications()
  from public, anon, authenticated;
revoke all on function public.admin_unread_merchant_notification_count()
  from public, anon, authenticated;
revoke all on function public.admin_mark_merchant_notification_read(bigint)
  from public, anon, authenticated;
grant execute on function public.admin_list_merchant_notifications()
  to authenticated;
grant execute on function public.admin_unread_merchant_notification_count()
  to authenticated;
grant execute on function public.admin_mark_merchant_notification_read(bigint)
  to authenticated;

-- Aggregation is performed in PostgreSQL using only the current merchant's
-- order-item snapshots. No buyer identity or customer contact details are
-- returned. Sales are gross paid item subtotals; order-level coupon discounts
-- are not allocated across merchants by the current schema.
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
grant execute on function public.merchant_sales_analytics()
  to authenticated;

commit;
