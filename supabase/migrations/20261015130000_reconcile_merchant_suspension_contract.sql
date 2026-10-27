begin;

-- Reconcile databases where 20261015110000 may already be recorded as
-- applied. This migration intentionally creates no admin helper and changes
-- no merchant or audit rows.
do $preflight$
declare
  v_helper oid := to_regprocedure('public.is_current_user_admin()')::oid;
  v_catalog_helper oid := to_regprocedure(
    'gocart_private.is_approved_product_merchant(uuid)'
  )::oid;
begin
  if to_regclass('public.merchant_status_audit') is null then
    raise exception 'SUSPENSION_RECONCILIATION_MISSING_AUDIT_TABLE';
  end if;
  if to_regclass('public.products') is null then
    raise exception 'SUSPENSION_RECONCILIATION_MISSING_PRODUCTS_TABLE';
  end if;
  if to_regprocedure('auth.uid()') is null then
    raise exception 'SUSPENSION_RECONCILIATION_MISSING_AUTH_UID';
  end if;
  if v_helper is null then
    raise exception 'SUSPENSION_RECONCILIATION_MISSING_CURRENT_USER_ADMIN';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_helper
      and p.prorettype = 'boolean'::regtype::oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_INVALID_CURRENT_USER_ADMIN';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.is_current_user_admin()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.is_current_user_admin()', 'EXECUTE'
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_INVALID_CURRENT_USER_ADMIN_GRANTS';
  end if;
  if v_catalog_helper is null then
    raise exception 'SUSPENSION_RECONCILIATION_MISSING_CATALOG_HELPER';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_catalog_helper
      and p.prorettype = 'boolean'::regtype::oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_INVALID_CATALOG_HELPER';
  end if;
  if not has_function_privilege(
    'anon', 'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated', 'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE'
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_INVALID_CATALOG_HELPER_GRANTS';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'public.merchant_status_audit'::regclass
      and a.attname = 'old_status'
      and a.attnum > 0
      and not a.attisdropped
      and pg_catalog.format_type(a.atttypid, a.atttypmod) = 'text'
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_AUDIT_OLD_STATUS_SCHEMA_MISMATCH';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.merchant_status_audit'::regclass
      and c.relrowsecurity
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_AUDIT_RLS_DISABLED';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.products'::regclass
      and c.relrowsecurity
  ) then
    raise exception 'SUSPENSION_RECONCILIATION_PRODUCTS_RLS_DISABLED';
  end if;
end;
$preflight$;

-- DROP NOT NULL preserves every existing audit value and leaves the existing
-- old_status CHECK constraint in place (SQL CHECK accepts NULL results).
alter table public.merchant_status_audit
  alter column old_status drop not null;

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

drop policy if exists "Authenticated approved merchant catalog is readable"
  on public.products;
drop policy if exists "Suspension catalog restriction for authenticated"
  on public.products;
create policy "Authenticated approved merchant catalog is readable"
  on public.products as permissive for select to authenticated
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
    or merchant_id = (select auth.uid())
    or (select public.is_current_user_admin())
  );
create policy "Suspension catalog restriction for authenticated"
  on public.products as restrictive for select to authenticated
  using (
    gocart_private.is_approved_product_merchant(merchant_id)
    or merchant_id = (select auth.uid())
    or (select public.is_current_user_admin())
  );

commit;
