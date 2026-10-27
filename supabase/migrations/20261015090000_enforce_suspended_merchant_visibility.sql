begin;

create table if not exists public.merchant_status_audit (
  id bigint generated always as identity primary key,
  merchant_id uuid not null,
  actor_id uuid not null,
  old_status text not null check (old_status in ('pending', 'approved', 'suspended')),
  new_status text not null check (new_status in ('approved', 'suspended')),
  reason text check (reason is null or length(reason) <= 500),
  changed_at timestamptz not null default now()
);

alter table public.merchant_status_audit enable row level security;
revoke all privileges on table public.merchant_status_audit
  from public, anon, authenticated;
grant select on table public.merchant_status_audit to authenticated;
drop policy if exists "Admins can view merchant status audit"
  on public.merchant_status_audit;
create policy "Admins can view merchant status audit"
  on public.merchant_status_audit for select to authenticated
  using ((select public.is_current_user_admin()));

-- Replace the old two-argument RPC to prevent unaudited status changes.
drop function if exists public.admin_set_merchant_status(uuid, text);
create or replace function public.admin_set_merchant_status(
  p_merchant_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_old_status text;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_actor_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_actor_id and p.role = 'admin'
  ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_status is null or p_status not in ('approved', 'suspended') then
    raise exception 'INVALID_MERCHANT_STATUS';
  end if;
  if v_reason is not null and length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  select p.merchant_status into v_old_status
  from public.profiles p
  where p.id = p_merchant_id and p.role = 'merchant'
  for update;
  if not found then raise exception 'MERCHANT_NOT_FOUND'; end if;
  if v_old_status = p_status then return; end if;

  update public.profiles p
  set merchant_status = p_status
  where p.id = p_merchant_id and p.role = 'merchant';

  insert into public.merchant_status_audit (
    merchant_id, actor_id, old_status, new_status, reason
  ) values (
    p_merchant_id, v_actor_id, v_old_status, p_status, v_reason
  );
end;
$function$;

revoke all on function public.admin_set_merchant_status(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_set_merchant_status(uuid, text, text)
  to authenticated;

-- Keep the catalog policy helper out of PostgREST's exposed public schema.
-- The helper reveals only a boolean and can only read the supplied merchant's
-- current status; callers cannot change merchant state through this function.
create schema if not exists gocart_private;
revoke all on schema gocart_private from public, anon, authenticated;
grant usage on schema gocart_private to anon, authenticated;

-- Suspension is reversible: products and historical orders remain untouched.
-- Public catalog visibility follows the merchant's current approved status.
create or replace function gocart_private.is_approved_product_merchant(
  p_merchant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_merchant_id
      and p.role = 'merchant'
      and p.merchant_status = 'approved'
  );
$function$;

revoke all on function gocart_private.is_approved_product_merchant(uuid)
  from public, anon, authenticated;
grant execute on function gocart_private.is_approved_product_merchant(uuid)
  to anon, authenticated;

drop policy if exists "Catalog is readable" on public.products;
drop policy if exists "Approved merchant catalog is readable" on public.products;
drop function if exists public.is_approved_product_merchant(uuid);

create policy "Approved merchant catalog is readable"
  on public.products for select to anon
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
  );

create policy "Authenticated approved merchant catalog is readable"
  on public.products for select to authenticated
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
    or merchant_id = (select auth.uid())
    or (select public.is_current_user_admin())
  );

-- Cart RPCs already lock products and enforce stock. This guard additionally
-- prevents stale clients from adding/updating cart lines for a suspended store.
create or replace function public.guard_active_merchant_cart_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_merchant_id uuid;
  v_merchant_role text;
  v_merchant_status text;
begin
  select p.merchant_id
    into v_merchant_id
  from public.products p
  where p.id = new.product_id;

  if not found then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;

  select p.role, p.merchant_status
    into v_merchant_role, v_merchant_status
  from public.profiles p
  where p.id = v_merchant_id
  for share;

  if not found
     or v_merchant_role is distinct from 'merchant'
     or v_merchant_status is distinct from 'approved' then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_active_merchant_cart_item()
  from public, anon, authenticated;
drop trigger if exists cart_items_require_approved_merchant_insert
  on public.cart_items;
drop trigger if exists cart_items_require_approved_merchant_update
  on public.cart_items;
create trigger cart_items_require_approved_merchant_insert
  before insert on public.cart_items
  for each row execute function public.guard_active_merchant_cart_item();
create trigger cart_items_require_approved_merchant_update
  before update of product_id, quantity on public.cart_items
  for each row execute function public.guard_active_merchant_cart_item();

-- The checkout transaction inserts order_items only after locking products.
-- This final guard prevents a suspended merchant from receiving a new order.
create or replace function public.guard_active_merchant_order_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_product_merchant_id uuid;
  v_merchant_role text;
  v_merchant_status text;
begin
  select p.merchant_id
    into v_product_merchant_id
  from public.products p
  where p.id = new.product_id;

  if not found
     or v_product_merchant_id is distinct from new.merchant_id then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;

  select p.role, p.merchant_status
    into v_merchant_role, v_merchant_status
  from public.profiles p
  where p.id = v_product_merchant_id
  for share;

  if not found
     or v_merchant_role is distinct from 'merchant'
     or v_merchant_status is distinct from 'approved' then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_active_merchant_order_item()
  from public, anon, authenticated;
drop trigger if exists order_items_require_approved_merchant
  on public.order_items;
create trigger order_items_require_approved_merchant
  before insert on public.order_items
  for each row execute function public.guard_active_merchant_order_item();

commit;
