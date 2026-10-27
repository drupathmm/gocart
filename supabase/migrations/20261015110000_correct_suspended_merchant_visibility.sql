begin;

-- Forward-only correction for the hosted schema. This migration deliberately
-- does not change products, orders, order_items history, or order status data.
--
-- The preflight makes schema assumptions explicit and aborts before changing
-- anything if the hosted tables or admin helper differ from the reviewed
-- contract.
do $preflight$
declare
  v_required record;
begin
  for v_required in
    select * from (values
      ('public.profiles', 'id', 'uuid'),
      ('public.profiles', 'role', 'text'),
      ('public.profiles', 'merchant_status', 'text'),
      ('public.products', 'id', 'bigint'),
      ('public.products', 'merchant_id', 'uuid'),
      ('public.cart_items', 'product_id', 'bigint'),
      ('public.cart_items', 'quantity', 'integer'),
      ('public.order_items', 'product_id', 'bigint'),
      ('public.order_items', 'merchant_id', 'uuid')
    ) as required(table_name, column_name, type_name)
  loop
    if to_regclass(v_required.table_name) is null then
      raise exception 'SUSPENSION_MIGRATION_MISSING_TABLE: %', v_required.table_name;
    end if;

    if not exists (
      select 1
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(v_required.table_name)
        and a.attname = v_required.column_name
        and a.attnum > 0
        and not a.attisdropped
        and pg_catalog.format_type(a.atttypid, a.atttypmod) = v_required.type_name
    ) then
      raise exception 'SUSPENSION_MIGRATION_SCHEMA_MISMATCH: %.% expected %',
        v_required.table_name, v_required.column_name, v_required.type_name;
    end if;
  end loop;

  if to_regprocedure('auth.uid()') is null then
    raise exception 'SUSPENSION_MIGRATION_MISSING_AUTH_UID';
  end if;
  if to_regprocedure('public.is_current_user_admin()') is null then
    raise exception 'SUSPENSION_MIGRATION_MISSING_CURRENT_USER_ADMIN';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = to_regprocedure('public.is_current_user_admin()')
      and p.prorettype = 'boolean'::regtype::oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'SUSPENSION_MIGRATION_INVALID_CURRENT_USER_ADMIN';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.is_current_user_admin()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.is_current_user_admin()', 'EXECUTE'
  ) then
    raise exception 'SUSPENSION_MIGRATION_CURRENT_USER_ADMIN_NOT_EXECUTABLE_BY_AUTHENTICATED';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.products'::regclass
      and c.relrowsecurity
  ) then
    raise exception 'SUSPENSION_MIGRATION_PRODUCTS_RLS_DISABLED';
  end if;
end;
$preflight$;

create table if not exists public.merchant_status_audit (
  id bigint generated always as identity primary key,
  merchant_id uuid not null,
  actor_id uuid not null,
  old_status text,
  new_status text not null,
  reason text check (reason is null or length(reason) <= 500),
  changed_at timestamptz not null default now(),
  constraint merchant_status_audit_new_status_check
    check (new_status in ('approved', 'suspended'))
);

-- If an audit table already exists, fail safely if it is incompatible rather
-- than silently writing incomplete audit records.
do $audit_preflight$
declare
  v_required record;
begin
  for v_required in
    select * from (values
      ('id', 'bigint'),
      ('merchant_id', 'uuid'),
      ('actor_id', 'uuid'),
      ('old_status', 'text'),
      ('new_status', 'text'),
      ('reason', 'text'),
      ('changed_at', 'timestamp with time zone')
    ) as required(column_name, type_name)
  loop
    if not exists (
      select 1
      from pg_catalog.pg_attribute a
      where a.attrelid = 'public.merchant_status_audit'::regclass
        and a.attname = v_required.column_name
        and a.attnum > 0
        and not a.attisdropped
        and pg_catalog.format_type(a.atttypid, a.atttypmod) = v_required.type_name
    ) then
      raise exception 'SUSPENSION_MIGRATION_AUDIT_SCHEMA_MISMATCH: % expected %',
        v_required.column_name, v_required.type_name;
    end if;
  end loop;

  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'public.merchant_status_audit'::regclass
      and a.attname = 'id'
      and a.attidentity in ('a', 'd')
  ) and not exists (
    select 1 from pg_catalog.pg_attrdef d
    join pg_catalog.pg_attribute a
      on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.merchant_status_audit'::regclass
      and a.attname = 'id'
  ) then
    raise exception 'SUSPENSION_MIGRATION_AUDIT_ID_HAS_NO_GENERATOR';
  end if;

end;
$audit_preflight$;

-- 0900 created this column NOT NULL. Relax only that constraint after the
-- table and column types have been verified; existing audit rows are retained.
alter table public.merchant_status_audit
  alter column old_status drop not null;

do $audit_nullability_check$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'public.merchant_status_audit'::regclass
      and a.attname = 'old_status'
      and a.attnotnull
  ) then
    raise exception 'SUSPENSION_MIGRATION_AUDIT_OLD_STATUS_MUST_ALLOW_NULL';
  end if;
end;
$audit_nullability_check$;

alter table public.merchant_status_audit enable row level security;
revoke all privileges on table public.merchant_status_audit
  from public, anon, authenticated;
grant select on table public.merchant_status_audit to authenticated;

drop policy if exists "Admins can view merchant status audit"
  on public.merchant_status_audit;
drop policy if exists "Merchant status audit admin restriction"
  on public.merchant_status_audit;
create policy "Admins can view merchant status audit"
  on public.merchant_status_audit for select to authenticated
  using ((select public.is_current_user_admin()));
create policy "Merchant status audit admin restriction"
  on public.merchant_status_audit as restrictive for select to authenticated
  using ((select public.is_current_user_admin()));

-- Replace the legacy RPC. The actor is always derived from the authenticated
-- request; no client-supplied actor ID is accepted.
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
  if v_old_status is not distinct from p_status then return; end if;

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

create schema if not exists gocart_private;
grant usage on schema gocart_private to anon, authenticated;

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

-- Drop the confirmed open policy and the names used by the earlier draft.
-- The restrictive policies below also constrain any other permissive SELECT
-- policy without removing its owner/admin access rules.
drop policy if exists "Anyone can view products" on public.products;
drop policy if exists "Catalog is readable" on public.products;
drop policy if exists "Approved merchant catalog is readable" on public.products;
drop policy if exists "Authenticated approved merchant catalog is readable"
  on public.products;
drop policy if exists "Suspension catalog restriction for anon"
  on public.products;
drop policy if exists "Suspension catalog restriction for authenticated"
  on public.products;

create policy "Approved merchant catalog is readable"
  on public.products as permissive for select to anon
  using (gocart_private.is_approved_product_merchant(merchant_id));

create policy "Authenticated approved merchant catalog is readable"
  on public.products as permissive for select to authenticated
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
    or merchant_id = (select auth.uid())
    or (select public.is_current_user_admin())
  );

create policy "Suspension catalog restriction for anon"
  on public.products as restrictive for select to anon
  using (gocart_private.is_approved_product_merchant(merchant_id));

create policy "Suspension catalog restriction for authenticated"
  on public.products as restrictive for select to authenticated
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
    or merchant_id = (select auth.uid())
    or (select public.is_current_user_admin())
  );

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
  select p.merchant_id into v_merchant_id
  from public.products p
  where p.id = new.product_id;

  if not found then raise exception 'MERCHANT_UNAVAILABLE'; end if;

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
  select p.merchant_id into v_product_merchant_id
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
