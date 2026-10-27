begin;

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  previous_status text check (
    previous_status is null
    or previous_status in (
      'pending', 'paid', 'shipped', 'cancelled', 'delivered',
      'return_requested', 'returned'
    )
  ),
  new_status text not null check (
    new_status in (
      'pending', 'paid', 'shipped', 'cancelled', 'delivered',
      'return_requested', 'returned'
    )
  ),
  changed_at timestamptz not null default now(),
  actor_id uuid references public.profiles (id) on delete restrict,
  actor_role text not null check (
    actor_role in ('user', 'merchant', 'admin', 'system')
  )
);

create index if not exists order_status_history_order_changed_idx
  on public.order_status_history (order_id, changed_at desc);

alter table public.order_status_history enable row level security;

revoke all privileges on table public.order_status_history
  from public, anon, authenticated, service_role;
grant select on table public.order_status_history to authenticated;

create policy "Buyers and admins can view order status history"
  on public.order_status_history for select to authenticated
  using (
    exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.user_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'admin'
    )
  );

create or replace function public.record_order_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role text;
begin
  if tg_op = 'UPDATE' and old.status is not distinct from new.status then
    return new;
  end if;

  if v_actor_id is null then
    if auth.role() is distinct from 'service_role' then
      raise exception 'NOT_AUTHENTICATED';
    end if;
    v_actor_role := 'system';
  else
    select p.role
      into v_actor_role
    from public.profiles p
    where p.id = v_actor_id;

    if v_actor_role is null or v_actor_role not in ('user', 'merchant', 'admin') then
      raise exception 'INVALID_STATUS_ACTOR';
    end if;
  end if;

  insert into public.order_status_history (
    order_id,
    previous_status,
    new_status,
    actor_id,
    actor_role
  )
  values (
    new.id,
    case when tg_op = 'INSERT' then null else old.status end,
    new.status,
    v_actor_id,
    v_actor_role
  );

  return new;
end;
$function$;

revoke all on function public.record_order_status_history()
  from public, anon, authenticated;

create or replace function public.reject_order_status_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'ORDER_STATUS_HISTORY_IMMUTABLE';
end;
$function$;

revoke all on function public.reject_order_status_history_mutation()
  from public, anon, authenticated;

create trigger order_status_history_record_insert
  after insert on public.orders
  for each row
  execute function public.record_order_status_history();

create trigger order_status_history_record_update
  after update of status on public.orders
  for each row
  when (old.status is distinct from new.status)
  execute function public.record_order_status_history();

create trigger order_status_history_immutable
  before update or delete on public.order_status_history
  for each row
  execute function public.reject_order_status_history_mutation();

-- Keep the existing transition function and cancellation behavior, but make
-- its SECURITY DEFINER name resolution independent of the caller's path.
alter function public.change_order_status(uuid, text) set search_path = '';
alter function public.cancel_own_order(uuid) set search_path = '';

-- Authenticated and anonymous API clients may read orders, but may not write
-- order state or fabricate history entries. Trusted functions perform writes.
revoke insert, update, delete on table public.orders, public.order_items
  from anon, authenticated;
revoke insert, update, delete on table public.order_status_history
  from anon, authenticated, service_role;

commit;
