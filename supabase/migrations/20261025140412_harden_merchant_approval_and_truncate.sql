begin;

-- Reassert the signup invariant without any session-setting override. The
-- trigger still supplies the auth email and rejects client-created admins.
create or replace function public.set_initial_profile_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is not null
     and (select auth.uid()) is distinct from new.id then
    raise exception 'PROFILE_OWNER_MISMATCH';
  end if;
  if new.role = 'admin' and (select auth.uid()) is not null then
    raise exception 'ADMIN_PROFILE_CREATION_NOT_ALLOWED';
  end if;
  select u.email into new.email
  from auth.users u
  where u.id = new.id;
  if new.email is null then raise exception 'AUTH_EMAIL_REQUIRED'; end if;
  if new.role = 'merchant' then
    new.merchant_status := 'pending';
  else
    new.merchant_status := 'approved';
  end if;
  return new;
end;
$function$;

revoke all on function public.set_initial_profile_status()
  from public, anon, authenticated, service_role;

-- No current application caller remains. Drop the historical compatibility
-- RPC rather than leave an authenticated self-approval-shaped endpoint exposed.
revoke all on function public.approve_my_merchant_account()
  from public, anon, authenticated;
drop function public.approve_my_merchant_account();

-- Preserve profile editing through its existing name-only column grant while
-- preventing table-level UPDATE grants from bypassing the status RPC.
revoke update on table public.profiles
  from public, anon, authenticated, service_role;
revoke update (merchant_status) on table public.profiles
  from public, anon, authenticated, service_role;
grant update (name) on table public.profiles to authenticated;

-- Reassert the intended grants explicitly, including service_role: neither
-- helper should become a callable API for a server-key client by default ACL.
revoke all on function public.is_current_user_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.is_current_user_admin() to authenticated;
revoke all on function public.admin_set_merchant_status(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_set_merchant_status(uuid, text, text)
  to authenticated;

revoke truncate on table public.products from public, anon, authenticated;

-- This repository currently creates offers, not promotions. If an older or
-- externally provisioned local schema has public.promotions, harden it too.
do $revoke_promotions_truncate$
begin
  if to_regclass('public.promotions') is not null then
    execute 'revoke truncate on table public.promotions from public, anon, authenticated';
  end if;
end;
$revoke_promotions_truncate$;

-- Fail the migration instead of leaving a partially hardened local schema.
do $verify_merchant_security$
declare
  v_profiles_oid oid := to_regclass('public.profiles')::oid;
  v_profile_trigger_oid oid := to_regprocedure(
    'public.set_initial_profile_status()'
  )::oid;
begin
  if to_regprocedure('public.approve_my_merchant_account()') is not null then
    raise exception 'MERCHANT_APPROVAL_COMPATIBILITY_RPC_REMAINS';
  end if;

  if v_profiles_oid is null then
    raise exception 'MERCHANT_SIGNUP_PROFILE_TABLE_MISSING';
  end if;
  if v_profile_trigger_oid is null then
    raise exception 'MERCHANT_SIGNUP_STATUS_TRIGGER_FUNCTION_MISSING';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    where p.oid = v_profile_trigger_oid
      and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%new.merchant_status := ''pending''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
  ) then
    raise exception 'MERCHANT_SIGNUP_STATUS_TRIGGER_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles_oid
      and t.tgname = 'profiles_set_initial_status'
      and t.tgfoid = v_profile_trigger_oid
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    raise exception 'MERCHANT_SIGNUP_STATUS_TRIGGER_INVALID';
  end if;

  if has_column_privilege('anon', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('service_role', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_table_privilege('service_role', 'public.profiles', 'UPDATE') then
    raise exception 'DIRECT_MERCHANT_STATUS_UPDATE_PRIVILEGE_REMAINS';
  end if;

  if to_regprocedure('public.is_current_user_admin()') is null
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = 'public.is_current_user_admin()'::regprocedure
         and p.prosecdef
         and p.proconfig @> array['search_path=""']
     )
     or not has_function_privilege(
       'authenticated', 'public.is_current_user_admin()', 'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.is_current_user_admin()', 'EXECUTE'
     )
     or has_function_privilege(
       'service_role', 'public.is_current_user_admin()', 'EXECUTE'
     ) then
    raise exception 'CURRENT_USER_ADMIN_HELPER_SECURITY_INVALID';
  end if;

  if to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is null
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure
         and p.prosecdef
         and p.proconfig @> array['search_path=""']
         and p.prosrc like '%auth.uid()%'
         and p.prosrc like '%p.role = ''admin''%'
         and p.prosrc like '%NOT_AUTHORIZED%'
     )
     or not has_function_privilege(
       'authenticated', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
     )
     or has_function_privilege(
       'anon', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
     )
     or has_function_privilege(
       'service_role', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
     ) then
    raise exception 'ADMIN_MERCHANT_STATUS_RPC_SECURITY_INVALID';
  end if;

  if has_table_privilege('anon', 'public.products', 'TRUNCATE')
     or has_table_privilege('authenticated', 'public.products', 'TRUNCATE') then
    raise exception 'CLIENT_PRODUCTS_TRUNCATE_PRIVILEGE_REMAINS';
  end if;

  if to_regclass('public.promotions') is not null then
    if has_table_privilege('anon', 'public.promotions', 'TRUNCATE')
       or has_table_privilege('authenticated', 'public.promotions', 'TRUNCATE') then
      raise exception 'CLIENT_PROMOTIONS_TRUNCATE_PRIVILEGE_REMAINS';
    end if;
  end if;
end;
$verify_merchant_security$;

commit;
