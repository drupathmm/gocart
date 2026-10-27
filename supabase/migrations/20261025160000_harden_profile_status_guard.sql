begin;

-- Repair the hosted profile guard drift. The earlier local hardening migration
-- removed the self-approval RPC and protected signup, but did not replace this
-- separately-installed UPDATE trigger function.
do $preflight_profile_status_guard$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.products') is null then
    raise exception 'PROFILE_STATUS_GUARD_REQUIRED_TABLE_MISSING';
  end if;

  if exists (
    select required.column_name
    from (values ('id'), ('email'), ('role'), ('created_at'), ('merchant_status'))
      as required_columns(column_name)
    where not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = 'public.profiles'::regclass
        and a.attname = required_columns.column_name
        and a.attnum > 0 and not a.attisdropped
    )
  ) then
    raise exception 'PROFILE_STATUS_GUARD_REQUIRED_COLUMN_MISSING';
  end if;

  if to_regprocedure('auth.uid()') is null
     or to_regprocedure('auth.role()') is null
     or to_regprocedure('public.is_current_user_admin()') is null
     or to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is null then
    raise exception 'PROFILE_STATUS_GUARD_REQUIRED_AUTHORIZATION_FUNCTION_MISSING';
  end if;
end;
$preflight_profile_status_guard$;

-- Keep identity fields immutable and role changes admin-only. Status changes
-- have one path: an authenticated administrator, normally through
-- admin_set_merchant_status(). The custom app.merchant_auto_approval setting
-- is deliberately not consulted.
create or replace function public.protect_profile_privileged_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_is_authenticated_admin boolean := false;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.created_at is distinct from old.created_at then
    raise exception using
      errcode = '42501',
      message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  if v_actor_id is not null
     and (select auth.role()) = 'authenticated' then
    select exists (
      select 1 from public.profiles p
      where p.id = v_actor_id and p.role = 'admin'
    ) into v_is_authenticated_admin;
  end if;

  if new.role is distinct from old.role
     and not v_is_authenticated_admin then
    raise exception using
      errcode = '42501',
      message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  if new.merchant_status is distinct from old.merchant_status
     and (
       not v_is_authenticated_admin
       or old.role is distinct from 'merchant'
       or new.role is distinct from 'merchant'
       or new.merchant_status is null
       or new.merchant_status not in ('approved', 'suspended')
     ) then
    raise exception using
      errcode = '42501',
      message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  return new;
end;
$function$;

revoke all on function public.protect_profile_privileged_fields()
  from public, anon, authenticated, service_role;

-- Preserve an existing trigger binding when present. Add an all-UPDATE guard
-- if the hosted schema has the function but no enabled BEFORE UPDATE trigger.
do $ensure_profile_status_trigger$
declare
  v_profiles_oid oid := to_regclass('public.profiles')::oid;
  v_guard_oid oid := to_regprocedure(
    'public.protect_profile_privileged_fields()'
  )::oid;
begin
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles_oid
      and t.tgfoid = v_guard_oid
      and (t.tgtype & 2) = 2
      and (t.tgtype & 16) = 16
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    if exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = v_profiles_oid
        and t.tgname = 'profiles_privileged_fields_guard'
        and t.tgfoid <> v_guard_oid
        and not t.tgisinternal
    ) then
      raise exception 'PROFILE_STATUS_GUARD_TRIGGER_NAME_CONFLICT';
    end if;

    if exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = v_profiles_oid
        and t.tgname = 'profiles_privileged_fields_guard'
        and t.tgfoid = v_guard_oid
        and not t.tgisinternal
    ) then
      execute 'drop trigger profiles_privileged_fields_guard on public.profiles';
    end if;

    execute 'create trigger profiles_privileged_fields_guard before update on public.profiles for each row execute function public.protect_profile_privileged_fields()';
  end if;
end;
$ensure_profile_status_trigger$;

-- Remove any remaining compatibility endpoint without CASCADE. A dependent
-- object should stop this migration for review rather than be removed silently.
do $drop_merchant_self_approval$
begin
  if to_regprocedure('public.approve_my_merchant_account()') is not null then
    execute 'revoke all on function public.approve_my_merchant_account() from public, anon, authenticated, service_role';
    execute 'drop function public.approve_my_merchant_account()';
  end if;
end;
$drop_merchant_self_approval$;

-- Keep client profile editing name-only. Signup INSERT and admin status changes
-- continue through their dedicated trigger and RPC paths.
revoke update on table public.profiles
  from public, anon, authenticated, service_role;
revoke update (id, name, email, role, created_at, merchant_status)
  on table public.profiles from public, anon, authenticated, service_role;
grant update (name) on table public.profiles to authenticated;

-- The admin RPC independently checks auth.uid() against profiles.role. Keep
-- direct table access and the admin helper unavailable to anon/service_role.
revoke all on function public.is_current_user_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.is_current_user_admin() to authenticated;
revoke all on function public.admin_set_merchant_status(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_set_merchant_status(uuid, text, text)
  to authenticated;

-- Fail this migration on an unexpected profile schema, trigger binding, or
-- permission state instead of recording a partial repair.
do $verify_profile_status_guard$
declare
  v_profiles_oid oid := to_regclass('public.profiles')::oid;
  v_guard_oid oid := to_regprocedure(
    'public.protect_profile_privileged_fields()'
  )::oid;
  v_signup_oid oid := to_regprocedure(
    'public.set_initial_profile_status()'
  )::oid;
begin
  if to_regprocedure('public.approve_my_merchant_account()') is not null then
    raise exception 'MERCHANT_SELF_APPROVAL_RPC_REMAINS';
  end if;

  if v_guard_oid is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_guard_oid
      and p.prorettype = 'trigger'::regtype::oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%auth.uid()%'
      and p.prosrc like '%auth.role()%'
      and p.prosrc like '%p.role = ''admin''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
  ) then
    raise exception 'PROFILE_PRIVILEGED_FIELD_GUARD_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles_oid
      and t.tgfoid = v_guard_oid
      and (t.tgtype & 2) = 2
      and (t.tgtype & 16) = 16
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    raise exception 'PROFILE_PRIVILEGED_FIELD_GUARD_TRIGGER_INVALID';
  end if;

  if v_signup_oid is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_signup_oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%new.merchant_status := ''pending''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
  ) or not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles_oid
      and t.tgname = 'profiles_set_initial_status'
      and t.tgfoid = v_signup_oid
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    raise exception 'MERCHANT_SIGNUP_STATUS_TRIGGER_INVALID';
  end if;

  if has_column_privilege('anon', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('service_role', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
     or not has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE')
     or has_table_privilege('service_role', 'public.profiles', 'UPDATE') then
    raise exception 'DIRECT_MERCHANT_STATUS_UPDATE_PRIVILEGE_REMAINS';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.is_current_user_admin()'::regprocedure
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
  ) or not has_function_privilege(
    'authenticated', 'public.is_current_user_admin()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.is_current_user_admin()', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.is_current_user_admin()', 'EXECUTE'
  ) then
    raise exception 'CURRENT_USER_ADMIN_HELPER_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%auth.uid()%'
      and p.prosrc like '%p.role = ''admin''%'
  ) or not has_function_privilege(
    'authenticated', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  ) then
    raise exception 'ADMIN_MERCHANT_STATUS_RPC_SECURITY_INVALID';
  end if;
end;
$verify_profile_status_guard$;

commit;
