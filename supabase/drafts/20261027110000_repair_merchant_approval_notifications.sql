-- REVIEW DRAFT ONLY. This file is outside supabase/migrations and must not be
-- run until the authorized GoCart owner confirms migration history and the
-- profile-trigger contract. No remote state has been inspected by this draft.

begin;

-- Fail closed unless the observed legacy objects still match the reported
-- repair starting point. Replace the guard function in place below; never
-- disable/recreate its already-enabled trigger and never set its legacy GUC.
do $preflight$
declare
  v_profiles oid := to_regclass('public.profiles')::oid;
  v_guard oid := to_regprocedure('public.protect_profile_privileged_fields()')::oid;
  v_signup oid := to_regprocedure('public.set_initial_profile_status()')::oid;
  v_admin_helper oid := to_regprocedure('public.is_current_user_admin()')::oid;
  v_expected_profile_triggers integer;
  v_name text;
begin
  if v_profiles is null or to_regclass('auth.users') is null
     or to_regprocedure('auth.uid()') is null
     or to_regprocedure('auth.role()') is null then
    raise exception 'MERCHANT_REPAIR_REQUIRED_PROFILES_OR_AUTH_UID_MISSING';
  end if;

  if exists (
    select 1 from (values ('id'),('name'),('email'),('role'),('merchant_status'),('created_at')) r(name)
    where not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = v_profiles and a.attname = r.name
        and a.attnum > 0 and not a.attisdropped
    )
  ) then
    raise exception 'MERCHANT_REPAIR_PROFILE_COLUMNS_MISMATCH';
  end if;

  if exists (
    select 1 from (values
      ('id','uuid',true),('name','text',true),('email','text',true),
      ('role','text',true),('merchant_status','text',true),
      ('created_at','timestamp with time zone',true)
    ) r(column_name,expected_type,expected_not_null)
    join pg_catalog.pg_attribute a on a.attrelid = v_profiles
      and a.attname = r.column_name and a.attnum > 0 and not a.attisdropped
    where pg_catalog.format_type(a.atttypid,a.atttypmod) is distinct from r.expected_type
       or a.attnotnull is distinct from r.expected_not_null
  ) then raise exception 'MERCHANT_REPAIR_PROFILE_COLUMN_CONTRACT_MISMATCH'; end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = v_profiles and c.contype = 'p'
      and pg_catalog.pg_get_constraintdef(c.oid) = 'PRIMARY KEY (id)'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = v_profiles and c.contype = 'f'
      and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c'
      and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
        where attrelid = v_profiles and attname = 'id')]::smallint[]
      and c.confkey = array[(select attnum::smallint from pg_catalog.pg_attribute
        where attrelid = 'auth.users'::regclass and attname = 'id')]::smallint[]
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = v_profiles and c.contype = 'c'
      and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
        where attrelid = v_profiles and attname = 'name')]::smallint[]
      and pg_catalog.pg_get_constraintdef(c.oid) like '%length(btrim(name))%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%100%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = v_profiles and c.contype = 'c'
      and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
        where attrelid = v_profiles and attname = 'role')]::smallint[]
      and pg_catalog.pg_get_constraintdef(c.oid) like '%user%merchant%admin%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = v_profiles and c.contype = 'c'
      and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
        where attrelid = v_profiles and attname = 'merchant_status')]::smallint[]
      and pg_catalog.pg_get_constraintdef(c.oid) like '%pending%approved%suspended%'
      and c.conname = 'profiles_merchant_status_check'
  ) or (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid = v_profiles and c.contype = 'c') <> 3
    or (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid = v_profiles) <> 5
  then raise exception 'MERCHANT_REPAIR_PROFILE_CONSTRAINT_MISMATCH'; end if;

  -- Defaults are part of the local base-schema contract. A changed default can
  -- silently create profiles outside the expected signup behavior.
  if exists (
    select 1
    from (values
      ('id',null::text),('name',null::text),('email',null::text),
      ('role',null::text),('merchant_status','''pending''::text'),
      ('created_at','now()')
    ) expected(column_name,expected_default)
    join pg_catalog.pg_attribute a on a.attrelid = v_profiles
      and a.attname = expected.column_name and a.attnum > 0 and not a.attisdropped
    left join pg_catalog.pg_attrdef d
      on d.adrelid = a.attrelid and d.adnum = a.attnum
    where (expected.expected_default is null and d.oid is not null)
       or (expected.expected_default is not null and
           (d.oid is null or pg_catalog.pg_get_expr(d.adbin,d.adrelid)
             is distinct from expected.expected_default))
  ) then raise exception 'MERCHANT_REPAIR_PROFILE_DEFAULT_MISMATCH'; end if;

  if not exists (select 1 from pg_catalog.pg_class c
      where c.oid = v_profiles and c.relrowsecurity)
     or (select count(*) from pg_catalog.pg_policies p
         where p.schemaname = 'public' and p.tablename = 'profiles') <> 3
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Profiles are readable by signed-in users'
         and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.qual like '%id =%' and p.qual like '%auth.uid()%'
         and p.qual like '%is_current_user_admin%')
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Users create their own non-admin profile'
         and p.cmd = 'INSERT' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.with_check like '%id =%' and p.with_check like '%auth.uid()%'
         and p.with_check like '%user%' and p.with_check like '%merchant%'
         and p.with_check not like '%admin%')
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Users update their own profile'
         and p.cmd = 'UPDATE' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.qual like '%id =%' and p.qual like '%auth.uid()%'
         and p.with_check like '%id =%' and p.with_check like '%auth.uid()%') then
    raise exception 'MERCHANT_REPAIR_PROFILE_RLS_POLICY_MISMATCH';
  end if;

  if v_guard is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_guard and p.prorettype = 'trigger'::regtype::oid
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%app.merchant_auto_approval%'
      and p.prosrc like '%new.merchant_status%'
      and p.prosrc like '%new.role%'
      and p.prosrc like '%auth.uid()%'
  ) or not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles and t.tgfoid = v_guard
      and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
      and t.tgenabled = 'O' and not t.tgisinternal
      and t.tgname = 'protect_profile_privileged_fields_trigger'
  ) then
    raise exception 'MERCHANT_REPAIR_PROFILE_GUARD_REQUIRES_SEPARATE_REVIEW';
  end if;
  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'protect_profile_privileged_fields') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'set_initial_profile_status') <> 1 then
    raise exception 'MERCHANT_REPAIR_PROFILE_FUNCTION_OVERLOAD_CONFLICT';
  end if;

  if v_signup is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_signup and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prorettype = 'trigger'::regtype::oid
      and p.prosrc like '%PROFILE_OWNER_MISMATCH%'
      and p.prosrc like '%ADMIN_PROFILE_CREATION_NOT_ALLOWED%'
      and p.prosrc like '%auth.users%'
      and p.prosrc like '%where u.id = new.id%'
      and p.prosrc like '%AUTH_EMAIL_REQUIRED%'
      and p.prosrc like '%new.merchant_status := ''pending''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
      and has_table_privilege(p.proowner,'auth.users','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles and t.tgfoid = v_signup
      and t.tgtype = 7 and t.tgenabled = 'O' and not t.tgisinternal
  ) then
    raise exception 'MERCHANT_REPAIR_SIGNUP_STATUS_GUARD_INVALID';
  end if;

  if v_admin_helper is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_admin_helper and p.prorettype = 'boolean'::regtype::oid
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%where p.id = (select auth.uid())%'
      and p.prosrc like '%p.role = ''admin''%'
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) then
    raise exception 'MERCHANT_REPAIR_ADMIN_HELPER_INVALID';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'is_current_user_admin') <> 1
     or not has_function_privilege('authenticated','public.is_current_user_admin()','EXECUTE')
     or has_function_privilege('anon','public.is_current_user_admin()','EXECUTE')
     or has_function_privilege('service_role','public.is_current_user_admin()','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_ADMIN_HELPER_OVERLOAD_OR_GRANT_MISMATCH';
  end if;

  if has_function_privilege('anon',v_guard,'EXECUTE')
     or has_function_privilege('authenticated',v_guard,'EXECUTE')
     or has_function_privilege('service_role',v_guard,'EXECUTE') then
    raise exception 'MERCHANT_REPAIR_PROFILE_GUARD_GRANT_MISMATCH';
  end if;

  if has_function_privilege('anon',v_signup,'EXECUTE')
     or has_function_privilege('authenticated',v_signup,'EXECUTE')
     or has_function_privilege('service_role',v_signup,'EXECUTE')
     or not has_table_privilege((select p.proowner from pg_catalog.pg_proc p where p.oid = v_signup),
       'auth.users','SELECT') then
    raise exception 'MERCHANT_REPAIR_SIGNUP_TRIGGER_FUNCTION_EXPOSED';
  end if;

  if not exists (select 1 from pg_catalog.pg_proc p
      where p.oid = v_guard and has_table_privilege(p.proowner,'public.profiles','SELECT')
        and exists (select 1 from pg_catalog.pg_roles r
          where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))) then
    raise exception 'MERCHANT_REPAIR_PROFILE_GUARD_OWNER_INVALID';
  end if;

  if has_table_privilege('anon','public.profiles','INSERT')
     or has_table_privilege('authenticated','public.profiles','INSERT')
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and has_column_privilege('anon',v_profiles,a.attname,'INSERT'))
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and a.attname not in ('id','name','email','role')
         and has_column_privilege('authenticated',v_profiles,a.attname,'INSERT'))
     or has_column_privilege('anon','public.profiles','merchant_status','INSERT')
     or has_column_privilege('authenticated','public.profiles','merchant_status','INSERT')
     or has_column_privilege('authenticated','public.profiles','created_at','INSERT')
     or not has_column_privilege('authenticated','public.profiles','id','INSERT')
     or not has_column_privilege('authenticated','public.profiles','name','INSERT')
     or not has_column_privilege('authenticated','public.profiles','email','INSERT')
     or not has_column_privilege('authenticated','public.profiles','role','INSERT') then
    raise exception 'MERCHANT_REPAIR_PROFILE_INSERT_PRIVILEGE_MISMATCH';
  end if;

  if has_table_privilege('anon','public.profiles','UPDATE')
     or has_table_privilege('authenticated','public.profiles','UPDATE')
     or has_table_privilege('service_role','public.profiles','UPDATE')
     or not has_column_privilege('authenticated','public.profiles','name','UPDATE')
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and a.attname <> 'name'
         and has_column_privilege('authenticated',v_profiles,a.attname,'UPDATE'))
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and (has_column_privilege('anon',v_profiles,a.attname,'UPDATE')
           or has_column_privilege('service_role',v_profiles,a.attname,'UPDATE')))
      then
    raise exception 'MERCHANT_REPAIR_PROFILE_UPDATE_PRIVILEGE_MISMATCH';
  end if;

  select count(*) into v_expected_profile_triggers
  from pg_catalog.pg_trigger t where t.tgrelid = v_profiles and not t.tgisinternal;
  if v_expected_profile_triggers <> 2
     or not exists (
       select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
         and t.tgfoid = v_signup and t.tgenabled = 'O' and t.tgtype = 7
         and not t.tgisinternal
     )
     or not exists (
       select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
         and t.tgfoid = v_guard and t.tgenabled = 'O' and t.tgtype = 19
         and t.tgname = 'protect_profile_privileged_fields_trigger'
         and not t.tgisinternal
     ) then
    raise exception 'MERCHANT_REPAIR_PROFILE_TRIGGER_INVENTORY_MISMATCH';
  end if;

  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgfoid in (v_guard,v_signup)
               and t.tgrelid <> v_profiles and not t.tgisinternal) then
    raise exception 'MERCHANT_REPAIR_PROFILE_GUARD_BOUND_ELSEWHERE';
  end if;

  if to_regprocedure('public.admin_set_merchant_status(uuid,text)') is null
     or to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is not null
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_set_merchant_status') <> 1
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = 'public.admin_set_merchant_status(uuid,text)'::regprocedure
         and p.pronargs = 2 and p.prorettype = 'void'::regtype::oid
         and p.proargnames = array['p_merchant_id','p_status']::text[]
         and p.prosecdef and p.proconfig @> array['search_path=""']
         and p.prosrc like '%auth.uid()%' and p.prosrc like '%p.role = ''admin''%'
        and has_table_privilege(p.proowner,'public.profiles','SELECT')
        and has_table_privilege(p.proowner,'public.profiles','UPDATE')
        and exists (select 1 from pg_catalog.pg_roles r
          where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
     ) or not has_function_privilege('authenticated',
        'public.admin_set_merchant_status(uuid,text)','EXECUTE')
       or has_function_privilege('anon',
        'public.admin_set_merchant_status(uuid,text)','EXECUTE')
       or has_function_privilege('service_role',
        'public.admin_set_merchant_status(uuid,text)','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_LEGACY_STATUS_RPC_MISMATCH';
  end if;

  -- Do not silently replace an RPC still referenced by catalog dependencies.
  -- DROP ... RESTRICT below remains the final check for dependencies PostgreSQL
  -- records, and this assertion makes them explicit in the preflight report.
  if exists (
    select 1 from pg_catalog.pg_depend d
    where d.refclassid = 'pg_catalog.pg_proc'::regclass
      and d.refobjid = 'public.admin_set_merchant_status(uuid,text)'::regprocedure
      and d.deptype not in ('i','e')
  ) then raise exception 'MERCHANT_REPAIR_STATUS_RPC_HAS_DEPENDENCIES'; end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'admin_list_merchant_notifications') <> 0 then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_RPC_ALREADY_EXISTS_REVIEW_REQUIRED';
  end if;

  if to_regprocedure('public.sync_admin_merchant_registration_notification()') is not null
     and exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgfoid = to_regprocedure('public.sync_admin_merchant_registration_notification()')
         and not t.tgisinternal
     ) then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_HELPER_ALREADY_BOUND_REVIEW_REQUIRED';
  end if;

  if exists (select 1 from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in (
          'sync_admin_merchant_registration_notification',
          'admin_unread_merchant_notification_count',
          'admin_mark_merchant_notification_read'
        )) then
    raise exception 'MERCHANT_REPAIR_PARTIAL_NOTIFICATION_RPC_REQUIRES_REVIEW';
  end if;
  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'sync_admin_merchant_registration_notification') > 1 then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_HELPER_OVERLOAD_CONFLICT';
  end if;
  if to_regprocedure('public.sync_admin_merchant_registration_notification()') is not null
     and not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.sync_admin_merchant_registration_notification()')
         and p.pronargs = 0 and p.prorettype = 'trigger'::regtype::oid
     ) then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_HELPER_SIGNATURE_CONFLICT';
  end if;
  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'sync_admin_merchant_registration_notification') > 0
     and to_regprocedure('public.sync_admin_merchant_registration_notification()') is null then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_HELPER_SIGNATURE_CONFLICT';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid in (
      to_regprocedure('public.admin_unread_merchant_notification_count()'),
      to_regprocedure('public.admin_mark_merchant_notification_read(bigint)')
    ) and (
      (p.proname = 'admin_unread_merchant_notification_count'
       and (p.pronargs <> 0 or p.prorettype <> 'integer'::regtype::oid))
      or (p.proname = 'admin_mark_merchant_notification_read'
       and (p.pronargs <> 1 or p.proargnames <> array['p_notification_id']::text[]
            or p.prorettype <> 'void'::regtype::oid))
    )
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_RPC_SIGNATURE_CONFLICT'; end if;

  if to_regprocedure('public.admin_unread_merchant_notification_count()') is not null
     and (not has_function_privilege('authenticated',
          'public.admin_unread_merchant_notification_count()','EXECUTE')
       or has_function_privilege('anon',
          'public.admin_unread_merchant_notification_count()','EXECUTE')
       or has_function_privilege('service_role',
          'public.admin_unread_merchant_notification_count()','EXECUTE')) then
    raise exception 'MERCHANT_REPAIR_UNREAD_RPC_GRANT_MISMATCH';
  end if;
  if to_regprocedure('public.admin_mark_merchant_notification_read(bigint)') is not null
     and (not has_function_privilege('authenticated',
          'public.admin_mark_merchant_notification_read(bigint)','EXECUTE')
       or has_function_privilege('anon',
          'public.admin_mark_merchant_notification_read(bigint)','EXECUTE')
       or has_function_privilege('service_role',
          'public.admin_mark_merchant_notification_read(bigint)','EXECUTE')) then
    raise exception 'MERCHANT_REPAIR_MARK_READ_RPC_GRANT_MISMATCH';
  end if;
  if to_regprocedure('public.sync_admin_merchant_registration_notification()') is not null
     and (has_function_privilege('anon',
          'public.sync_admin_merchant_registration_notification()','EXECUTE')
       or has_function_privilege('authenticated',
          'public.sync_admin_merchant_registration_notification()','EXECUTE')
       or has_function_privilege('service_role',
          'public.sync_admin_merchant_registration_notification()','EXECUTE')) then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_HELPER_GRANT_MISMATCH';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'admin_unread_merchant_notification_count') > 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_mark_merchant_notification_read') > 1 then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_RPC_OVERLOAD_CONFLICT';
  end if;
  if ((select count(*) from pg_catalog.pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'admin_unread_merchant_notification_count') > 0
      and to_regprocedure('public.admin_unread_merchant_notification_count()') is null)
     or ((select count(*) from pg_catalog.pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'admin_mark_merchant_notification_read') > 0
      and to_regprocedure('public.admin_mark_merchant_notification_read(bigint)') is null) then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_RPC_SIGNATURE_CONFLICT';
  end if;

  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles
      and t.tgname in ('profiles_admin_merchant_notification_insert','profiles_admin_merchant_notification_status')
      and not t.tgisinternal
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_TRIGGER_ALREADY_EXISTS_REVIEW_REQUIRED'; end if;

  for v_name in select unnest(array[
    'merchant_status_audit',
    'admin_merchant_notifications',
    'admin_merchant_notification_reads'
  ]) loop
    if to_regclass('public.' || v_name) is not null then
      raise exception 'MERCHANT_REPAIR_OBJECT_ALREADY_EXISTS_REVIEW_REQUIRED: %', v_name;
    end if;
  end loop;
  if exists (select 1 from pg_catalog.pg_class c
      where c.relnamespace = 'public'::regnamespace
        and c.relname in (
          'merchant_status_audit_id_seq',
          'admin_merchant_notifications_id_seq'
        )) then
    raise exception 'MERCHANT_REPAIR_ORPHANED_IDENTITY_SEQUENCE';
  end if;
end;
$preflight$;

-- Extend the existing CHECK for explicit rejection. Existing profile rows,
-- including the seven customer rows with NULL merchant_status, are preserved.
alter table public.profiles
  drop constraint profiles_merchant_status_check;
alter table public.profiles
  add constraint profiles_merchant_status_check
  check (merchant_status in ('pending','approved','suspended','rejected'));

-- Reassert the local signup contract in place. This keeps the enabled trigger
-- binding while ensuring caller ownership, no client-created admins, and the
-- auth.users email remain enforced by the trusted trigger function.
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
  select u.email into new.email from auth.users u where u.id = new.id;
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
  from public,anon,authenticated,service_role;

-- Normalize the admin helper because the repair's RLS policies depend on its
-- exact auth.uid()-to-profile role check. Preserve its authenticated-only API.
create or replace function public.is_current_user_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$function$;
revoke all on function public.is_current_user_admin()
  from public,anon,authenticated,service_role;
grant execute on function public.is_current_user_admin() to authenticated;

-- Replace the legacy custom-setting branch in the existing function object.
-- PostgreSQL keeps the enabled trigger's binding because the signature is
-- unchanged. Only an authenticated admin may change privileged profile fields.
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
  if tg_op <> 'UPDATE' then return new; end if;

  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '42501', message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  if v_actor_id is not null and (select auth.role()) = 'authenticated' then
    select exists (
      select 1 from public.profiles p
      where p.id = v_actor_id and p.role = 'admin'
    ) into v_is_authenticated_admin;
  end if;

  if new.role is distinct from old.role and not v_is_authenticated_admin then
    raise exception using errcode = '42501', message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  if new.merchant_status is distinct from old.merchant_status and (
    not v_is_authenticated_admin
    or old.role is distinct from 'merchant'
    or new.role is distinct from 'merchant'
    or new.merchant_status is null
    or new.merchant_status not in ('approved','suspended','rejected')
  ) then
    raise exception using errcode = '42501', message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;
  return new;
end;
$function$;
revoke all on function public.protect_profile_privileged_fields()
  from public,anon,authenticated,service_role;

-- The local app and Edge Function sources contain no trusted service-role
-- profile-status writer; status changes use the authenticated, admin-checked
-- RPC. Match the hardened profile contract instead of retaining a broad
-- service_role UPDATE path that could bypass audit/transition validation.
-- Deployments with an external worker must verify that it does not write here.
revoke update on table public.profiles from public,anon,authenticated,service_role;
revoke update (id,name,email,role,created_at,merchant_status)
  on table public.profiles from public,anon,authenticated,service_role;
grant update (name) on table public.profiles to authenticated;

-- Exact local audit shape. Deliberately no profile foreign keys: audit history
-- survives profile deletion. old_status is nullable per the later local fix.
create table public.merchant_status_audit (
  id bigint generated always as identity primary key,
  merchant_id uuid not null,
  actor_id uuid not null,
  old_status text check (old_status is null or old_status in ('pending','approved','suspended','rejected')),
  new_status text not null check (new_status in ('approved','suspended','rejected')),
  reason text not null check (length(btrim(reason)) >= 1 and length(btrim(reason)) <= 500),
  changed_at timestamptz not null default now()
);
alter table public.merchant_status_audit alter column old_status drop not null;

create table public.admin_merchant_notifications (
  id bigint generated always as identity primary key,
  merchant_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null default 'pending_registration'
    check (event_type = 'pending_registration'),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_status text check (resolved_status is null or resolved_status in ('approved','suspended','rejected')),
  constraint admin_merchant_notifications_event_key unique (merchant_id,event_type)
);
create index admin_merchant_notifications_created_idx
  on public.admin_merchant_notifications (created_at desc);

create table public.admin_merchant_notification_reads (
  notification_id bigint not null references public.admin_merchant_notifications(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notification_id,admin_id)
);

-- IF NOT EXISTS must not conceal incompatible partial tables.
do $verify_tables$
begin
  if exists (
    select 1 from (values
      ('merchant_status_audit','id'),('merchant_status_audit','merchant_id'),
      ('merchant_status_audit','actor_id'),('merchant_status_audit','old_status'),
      ('merchant_status_audit','new_status'),('merchant_status_audit','reason'),
      ('merchant_status_audit','changed_at'),
      ('admin_merchant_notifications','id'),('admin_merchant_notifications','merchant_id'),
      ('admin_merchant_notifications','event_type'),('admin_merchant_notifications','created_at'),
      ('admin_merchant_notifications','resolved_at'),('admin_merchant_notifications','resolved_status'),
      ('admin_merchant_notification_reads','notification_id'),
      ('admin_merchant_notification_reads','admin_id'),('admin_merchant_notification_reads','read_at')
    ) r(table_name,column_name)
    where not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass('public.' || r.table_name)
        and a.attname = r.column_name and a.attnum > 0 and not a.attisdropped
    )
  ) then raise exception 'MERCHANT_REPAIR_TABLE_COLUMNS_MISMATCH'; end if;

  if exists (
    select 1 from (values
      ('merchant_status_audit','id','bigint',true),
      ('merchant_status_audit','merchant_id','uuid',true),
      ('merchant_status_audit','actor_id','uuid',true),
      ('merchant_status_audit','old_status','text',false),
      ('merchant_status_audit','new_status','text',true),
      ('merchant_status_audit','reason','text',true),
      ('merchant_status_audit','changed_at','timestamp with time zone',true),
      ('admin_merchant_notifications','id','bigint',true),
      ('admin_merchant_notifications','merchant_id','uuid',true),
      ('admin_merchant_notifications','event_type','text',true),
      ('admin_merchant_notifications','created_at','timestamp with time zone',true),
      ('admin_merchant_notifications','resolved_at','timestamp with time zone',false),
      ('admin_merchant_notifications','resolved_status','text',false),
      ('admin_merchant_notification_reads','notification_id','bigint',true),
      ('admin_merchant_notification_reads','admin_id','uuid',true),
      ('admin_merchant_notification_reads','read_at','timestamp with time zone',true)
    ) r(table_name,column_name,expected_type,expected_not_null)
    join pg_catalog.pg_attribute a
      on a.attrelid = to_regclass('public.' || r.table_name)
     and a.attname = r.column_name and a.attnum > 0 and not a.attisdropped
    where pg_catalog.format_type(a.atttypid,a.atttypmod) is distinct from r.expected_type
       or a.attnotnull is distinct from r.expected_not_null
  ) then raise exception 'MERCHANT_REPAIR_TABLE_COLUMN_TYPES_MISMATCH'; end if;

  if exists (
    select 1 from (values
      ('merchant_status_audit','id'),
      ('admin_merchant_notifications','id')
    ) r(table_name,column_name)
    join pg_catalog.pg_attribute a
      on a.attrelid = to_regclass('public.' || r.table_name)
     and a.attname = r.column_name and a.attnum > 0 and not a.attisdropped
    where coalesce(a.attidentity,'') not in ('a','d')
  ) then raise exception 'MERCHANT_REPAIR_IDENTITY_COLUMNS_MISMATCH'; end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notifications'::regclass
      and c.conname = 'admin_merchant_notifications_event_key' and c.contype = 'u'
      and c.conkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notifications'::regclass and attname = 'merchant_id'),
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notifications'::regclass and attname = 'event_type')
      ]::smallint[]
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notification_reads'::regclass
      and c.contype = 'p'
      and pg_catalog.pg_get_constraintdef(c.oid) = 'PRIMARY KEY (notification_id, admin_id)'
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_UNIQUENESS_MISSING'; end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.merchant_status_audit'::regclass
      and c.contype = 'p' and pg_catalog.pg_get_constraintdef(c.oid) = 'PRIMARY KEY (id)'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notifications'::regclass
      and c.contype = 'p' and pg_catalog.pg_get_constraintdef(c.oid) = 'PRIMARY KEY (id)'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notifications'::regclass
      and c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
      and c.confdeltype = 'c' and c.conkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notifications'::regclass and attname = 'merchant_id')
      ]::smallint[] and c.confkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.profiles'::regclass and attname = 'id')
      ]::smallint[]
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notification_reads'::regclass
      and c.contype = 'f' and c.confrelid = 'public.admin_merchant_notifications'::regclass
      and c.confdeltype = 'c' and c.conkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notification_reads'::regclass and attname = 'notification_id')
      ]::smallint[] and c.confkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notifications'::regclass and attname = 'id')
      ]::smallint[]
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notification_reads'::regclass
      and c.contype = 'f' and c.confrelid = 'public.profiles'::regclass
      and c.confdeltype = 'c' and c.conkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.admin_merchant_notification_reads'::regclass and attname = 'admin_id')
      ]::smallint[] and c.confkey = array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = 'public.profiles'::regclass and attname = 'id')
      ]::smallint[]
  ) then raise exception 'MERCHANT_REPAIR_PRIMARY_OR_FOREIGN_KEY_MISMATCH'; end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.merchant_status_audit'::regclass
      and c.contype = 'c' and pg_catalog.pg_get_constraintdef(c.oid) like '%old_status%pending%approved%suspended%rejected%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.merchant_status_audit'::regclass
      and c.contype = 'c' and pg_catalog.pg_get_constraintdef(c.oid) like '%new_status%approved%suspended%rejected%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.merchant_status_audit'::regclass
      and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%btrim(reason)%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%>= 1%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%<= 500%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notifications'::regclass
      and c.contype = 'c' and pg_catalog.pg_get_constraintdef(c.oid) like '%event_type%pending_registration%'
  ) or not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.admin_merchant_notifications'::regclass
      and c.contype = 'c' and pg_catalog.pg_get_constraintdef(c.oid) like '%resolved_status%approved%suspended%rejected%'
  ) then raise exception 'MERCHANT_REPAIR_CHECK_CONSTRAINT_MISMATCH'; end if;

  if exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid in (
      'public.merchant_status_audit'::regclass,
      'public.admin_merchant_notifications'::regclass,
      'public.admin_merchant_notification_reads'::regclass
    ) and not c.convalidated
  ) then raise exception 'MERCHANT_REPAIR_UNVALIDATED_TABLE_CONSTRAINT'; end if;

  if not exists (
    select 1 from pg_catalog.pg_class i
    join pg_catalog.pg_index x on x.indexrelid = i.oid
    where i.relnamespace = 'public'::regnamespace
      and i.relname = 'admin_merchant_notifications_created_idx'
      and x.indrelid = 'public.admin_merchant_notifications'::regclass
      and x.indisvalid and x.indisready
      and pg_catalog.pg_get_indexdef(i.oid) like '%(created_at DESC)%'
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_INDEX_MISMATCH'; end if;
end;
$verify_tables$;

alter table public.merchant_status_audit enable row level security;
alter table public.admin_merchant_notifications enable row level security;
alter table public.admin_merchant_notification_reads enable row level security;
revoke all privileges on table public.merchant_status_audit from public,anon,authenticated;
revoke all privileges on table public.merchant_status_audit from service_role;
grant select on table public.merchant_status_audit to authenticated;
drop policy if exists "Admins can view merchant status audit" on public.merchant_status_audit;
drop policy if exists "Merchant status audit admin restriction" on public.merchant_status_audit;
create policy "Admins can view merchant status audit"
  on public.merchant_status_audit for select to authenticated
  using ((select public.is_current_user_admin()));
create policy "Merchant status audit admin restriction"
  on public.merchant_status_audit as restrictive for select to authenticated
  using ((select public.is_current_user_admin()));
revoke all privileges on table public.admin_merchant_notifications from public,anon,authenticated;
revoke all privileges on table public.admin_merchant_notification_reads from public,anon,authenticated;
revoke all privileges on table public.admin_merchant_notifications,public.admin_merchant_notification_reads
  from service_role;

create or replace function public.sync_admin_merchant_registration_notification()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if new.role = 'merchant' and new.merchant_status = 'pending' then
    insert into public.admin_merchant_notifications (merchant_id,event_type)
    values (new.id,'pending_registration') on conflict (merchant_id,event_type) do nothing;
  elsif new.role = 'merchant' and new.merchant_status in ('approved','suspended','rejected') then
    update public.admin_merchant_notifications n
    set resolved_at = coalesce(n.resolved_at,now()), resolved_status = new.merchant_status
    where n.merchant_id = new.id and n.event_type = 'pending_registration';
  end if;
  return new;
end;
$function$;
revoke all on function public.sync_admin_merchant_registration_notification()
  from public,anon,authenticated,service_role;

do $ensure_notification_triggers$
declare
  v_profiles oid := 'public.profiles'::regclass::oid;
  v_sync oid := 'public.sync_admin_merchant_registration_notification()'::regprocedure::oid;
begin
  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles
      and t.tgname in ('profiles_admin_merchant_notification_insert','profiles_admin_merchant_notification_status')
      and t.tgfoid <> v_sync and not t.tgisinternal
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_TRIGGER_NAME_CONFLICT'; end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
      and t.tgname = 'profiles_admin_merchant_notification_insert'
      and t.tgfoid = v_sync and t.tgenabled = 'O' and not t.tgisinternal
  ) then
    execute 'create trigger profiles_admin_merchant_notification_insert after insert on public.profiles for each row execute function public.sync_admin_merchant_registration_notification()';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
      and t.tgname = 'profiles_admin_merchant_notification_status'
      and t.tgfoid = v_sync and t.tgenabled = 'O' and not t.tgisinternal
  ) then
    execute 'create trigger profiles_admin_merchant_notification_status after update of role,merchant_status on public.profiles for each row execute function public.sync_admin_merchant_registration_notification()';
  end if;
end;
$ensure_notification_triggers$;

-- Additive, deduplicated pending-registration backfill from the source migration.
insert into public.admin_merchant_notifications (merchant_id,event_type)
select p.id,'pending_registration' from public.profiles p
where p.role = 'merchant' and p.merchant_status = 'pending'
on conflict (merchant_id,event_type) do nothing;

create or replace function public.admin_set_merchant_status(
  p_merchant_id uuid,p_status text,p_reason text
)
returns void language plpgsql security definer set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_old_status text;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if v_actor_id is null or (select auth.role()) is distinct from 'authenticated' or not exists (
    select 1 from public.profiles p where p.id = v_actor_id and p.role = 'admin'
  ) then raise exception 'NOT_AUTHORIZED'; end if;
  if p_status is null or p_status not in ('approved','suspended','rejected') then
    raise exception 'INVALID_MERCHANT_STATUS';
  end if;
  if v_reason is null or length(v_reason) > 500 then raise exception 'INVALID_REASON'; end if;

  select p.merchant_status into v_old_status from public.profiles p
  where p.id = p_merchant_id and p.role = 'merchant' for update;
  if not found then raise exception 'MERCHANT_NOT_FOUND'; end if;
  if v_old_status = 'suspended' and p_status = 'approved' then
    raise exception 'REINSTATEMENT_REQUEST_REQUIRED';
  end if;
  if v_old_status = p_status then return; end if;

  if not ((v_old_status = 'pending' and p_status in ('approved','rejected'))
       or (v_old_status = 'approved' and p_status = 'suspended')) then
    raise exception 'INVALID_MERCHANT_STATUS_TRANSITION';
  end if;

  update public.profiles p set merchant_status = p_status
  where p.id = p_merchant_id and p.role = 'merchant';
  insert into public.merchant_status_audit
    (merchant_id,actor_id,old_status,new_status,reason)
  values (p_merchant_id,v_actor_id,v_old_status,p_status,v_reason);
end;
$function$;

-- RESTRICT is intentional: dependencies on the obsolete overload stop review.
drop function if exists public.admin_set_merchant_status(uuid,text) restrict;
revoke all on function public.admin_set_merchant_status(uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_set_merchant_status(uuid,text,text) to authenticated;

create or replace function public.admin_list_merchant_notifications()
returns table (
  notification_id bigint,merchant_id uuid,merchant_name text,merchant_email text,
  merchant_created_at timestamptz,merchant_status text,notification_created_at timestamptz,
  resolved_at timestamptz,resolved_status text,read_at timestamptz
)
language plpgsql security definer set search_path = ''
as $function$
declare v_admin_id uuid := (select auth.uid());
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p where p.id = v_admin_id and p.role = 'admin'
  ) then raise exception 'NOT_AUTHORIZED'; end if;
  return query
  select n.id,p.id,p.name,p.email,p.created_at,p.merchant_status,
         n.created_at,n.resolved_at,n.resolved_status,r.read_at
  from public.admin_merchant_notifications n
  join public.profiles p on p.id = n.merchant_id
  left join public.admin_merchant_notification_reads r
    on r.notification_id = n.id and r.admin_id = v_admin_id
  where n.resolved_at is null order by n.created_at desc limit 100;
end;
$function$;

-- Keep companion methods because the current dashboard calls them too.
create or replace function public.admin_unread_merchant_notification_count()
returns integer language plpgsql security definer set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_count integer;
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p where p.id = v_admin_id and p.role = 'admin'
  ) then raise exception 'NOT_AUTHORIZED'; end if;
  select count(*)::integer into v_count from public.admin_merchant_notifications n
  left join public.admin_merchant_notification_reads r
    on r.notification_id = n.id and r.admin_id = v_admin_id
  where n.resolved_at is null and r.notification_id is null;
  return coalesce(v_count,0);
end;
$function$;

create or replace function public.admin_mark_merchant_notification_read(p_notification_id bigint)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_admin_id uuid := (select auth.uid());
begin
  if v_admin_id is null or not exists (
    select 1 from public.profiles p where p.id = v_admin_id and p.role = 'admin'
  ) then raise exception 'NOT_AUTHORIZED'; end if;
  insert into public.admin_merchant_notification_reads as existing_read
    (notification_id,admin_id,read_at)
  select n.id,v_admin_id,now() from public.admin_merchant_notifications n
  where n.id = p_notification_id
  on conflict (notification_id,admin_id) do update
    set read_at = coalesce(existing_read.read_at,excluded.read_at);
  if not found then raise exception 'NOTIFICATION_NOT_FOUND'; end if;
end;
$function$;

revoke all on function public.admin_list_merchant_notifications()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_unread_merchant_notification_count()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_mark_merchant_notification_read(bigint)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_list_merchant_notifications() to authenticated;
grant execute on function public.admin_unread_merchant_notification_count() to authenticated;
grant execute on function public.admin_mark_merchant_notification_read(bigint) to authenticated;

do $postflight$
declare
  v_profiles oid := 'public.profiles'::regclass::oid;
  v_signup oid := 'public.set_initial_profile_status()'::regprocedure::oid;
  v_guard oid := 'public.protect_profile_privileged_fields()'::regprocedure::oid;
  v_admin_helper oid := 'public.is_current_user_admin()'::regprocedure::oid;
  v_sync oid := 'public.sync_admin_merchant_registration_notification()'::regprocedure::oid;
begin
  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in (
          'set_initial_profile_status','protect_profile_privileged_fields',
          'is_current_user_admin','admin_set_merchant_status',
          'sync_admin_merchant_registration_notification',
          'admin_list_merchant_notifications','admin_unread_merchant_notification_count',
          'admin_mark_merchant_notification_read'
        )) <> 8
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_set_merchant_status') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_list_merchant_notifications') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'is_current_user_admin') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'set_initial_profile_status') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'protect_profile_privileged_fields') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'sync_admin_merchant_registration_notification') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_unread_merchant_notification_count') <> 1
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_mark_merchant_notification_read') <> 1 then
    raise exception 'MERCHANT_REPAIR_UNEXPECTED_FUNCTION_OVERLOAD';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_signup and p.prosecdef
      and p.prorettype = 'trigger'::regtype::oid
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%auth.uid()%'
      and p.prosrc like '%new.id%'
      and p.prosrc like '%ADMIN_PROFILE_CREATION_NOT_ALLOWED%'
      and p.prosrc like '%auth.users%'
      and p.prosrc like '%AUTH_EMAIL_REQUIRED%'
      and p.prosrc like '%new.merchant_status := ''pending''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
      and has_table_privilege(p.proowner,'auth.users','SELECT')
  ) or has_function_privilege('anon',v_signup,'EXECUTE')
    or has_function_privilege('authenticated',v_signup,'EXECUTE')
    or has_function_privilege('service_role',v_signup,'EXECUTE')
    or not exists (select 1 from pg_catalog.pg_proc p
      where p.oid = v_signup
        and has_table_privilege(p.proowner,'auth.users','SELECT')) then
    raise exception 'MERCHANT_REPAIR_SIGNUP_FUNCTION_POSTFLIGHT_FAILED';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_admin_helper and p.prosecdef
      and p.prorettype = 'boolean'::regtype::oid
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%public.profiles%'
      and p.prosrc like '%auth.uid()%'
      and p.prosrc like '%p.role = ''admin''%'
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not has_function_privilege('authenticated',v_admin_helper,'EXECUTE')
    or has_function_privilege('anon',v_admin_helper,'EXECUTE')
    or has_function_privilege('service_role',v_admin_helper,'EXECUTE') then
    raise exception 'MERCHANT_REPAIR_ADMIN_HELPER_POSTFLIGHT_FAILED';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p where p.oid = v_guard
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%auth.uid()%' and p.prosrc like '%auth.role()%'
      and p.prosrc like '%p.role = ''admin''%'
      and p.prosrc not like '%app.merchant_auto_approval%'
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not exists (
    select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
      and t.tgname = 'protect_profile_privileged_fields_trigger'
      and t.tgfoid = v_guard and t.tgtype = 19
      and t.tgenabled = 'O' and not t.tgisinternal
  ) or has_function_privilege('anon', v_guard, 'EXECUTE')
    or has_function_privilege('authenticated', v_guard, 'EXECUTE')
    or has_function_privilege('service_role', v_guard, 'EXECUTE') then
    raise exception 'MERCHANT_REPAIR_PROFILE_GUARD_POSTFLIGHT_FAILED';
  end if;

  if has_table_privilege('anon','public.profiles','UPDATE')
     or has_table_privilege('authenticated','public.profiles','UPDATE')
     or has_table_privilege('service_role','public.profiles','UPDATE')
     or has_column_privilege('anon','public.profiles','name','UPDATE')
     or not has_column_privilege('authenticated','public.profiles','name','UPDATE')
     or has_column_privilege('anon','public.profiles','role','UPDATE')
     or has_column_privilege('service_role','public.profiles','name','UPDATE')
     or has_column_privilege('service_role','public.profiles','role','UPDATE')
     or has_column_privilege('service_role','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('authenticated','public.profiles','role','UPDATE')
     or has_column_privilege('anon','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('authenticated','public.profiles','merchant_status','UPDATE')
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and a.attname <> 'name'
         and has_column_privilege('authenticated',v_profiles,a.attname,'UPDATE'))
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and (has_column_privilege('anon',v_profiles,a.attname,'UPDATE')
           or has_column_privilege('service_role',v_profiles,a.attname,'UPDATE')))
     or has_table_privilege('service_role','public.profiles','UPDATE') then
    raise exception 'MERCHANT_REPAIR_DIRECT_PRIVILEGE_POSTFLIGHT_FAILED';
  end if;

  if has_table_privilege('anon','public.profiles','INSERT')
     or has_table_privilege('authenticated','public.profiles','INSERT')
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and has_column_privilege('anon',v_profiles,a.attname,'INSERT'))
     or exists (select 1 from pg_catalog.pg_attribute a
       where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
         and a.attname not in ('id','name','email','role')
         and has_column_privilege('authenticated',v_profiles,a.attname,'INSERT'))
     or has_column_privilege('authenticated','public.profiles','merchant_status','INSERT')
     or has_column_privilege('authenticated','public.profiles','created_at','INSERT')
     or not has_column_privilege('authenticated','public.profiles','id','INSERT')
     or not has_column_privilege('authenticated','public.profiles','name','INSERT')
     or not has_column_privilege('authenticated','public.profiles','email','INSERT')
     or not has_column_privilege('authenticated','public.profiles','role','INSERT') then
    raise exception 'MERCHANT_REPAIR_PROFILE_INSERT_POSTFLIGHT_FAILED';
  end if;

  if exists (
    select 1 from (values
      ('id','uuid',true),('name','text',true),('email','text',true),
      ('role','text',true),('merchant_status','text',true),
      ('created_at','timestamp with time zone',true)
    ) expected(column_name,expected_type,expected_not_null)
    join pg_catalog.pg_attribute a on a.attrelid = v_profiles
      and a.attname = expected.column_name and a.attnum > 0 and not a.attisdropped
    where pg_catalog.format_type(a.atttypid,a.atttypmod) is distinct from expected.expected_type
       or a.attnotnull is distinct from expected.expected_not_null
  ) or (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid = v_profiles and c.contype = 'c') <> 3
    or (select count(*) from pg_catalog.pg_constraint c
       where c.conrelid = v_profiles) <> 5
    or not exists (select 1 from pg_catalog.pg_constraint c
      where c.conrelid = v_profiles and c.contype = 'p'
        and pg_catalog.pg_get_constraintdef(c.oid) = 'PRIMARY KEY (id)')
    or not exists (select 1 from pg_catalog.pg_constraint c
      where c.conrelid = v_profiles and c.contype = 'f'
        and c.confrelid = 'auth.users'::regclass and c.confdeltype = 'c')
    or not exists (select 1 from pg_catalog.pg_constraint c
      where c.conrelid = v_profiles and c.contype = 'c'
        and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
          where attrelid = v_profiles and attname = 'name')]::smallint[]
        and pg_catalog.pg_get_constraintdef(c.oid) like '%length(btrim(name))%'
        and pg_catalog.pg_get_constraintdef(c.oid) like '%100%')
    or not exists (select 1 from pg_catalog.pg_constraint c
      where c.conrelid = v_profiles and c.contype = 'c'
        and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
          where attrelid = v_profiles and attname = 'role')]::smallint[]
        and pg_catalog.pg_get_constraintdef(c.oid) like '%user%merchant%admin%')
    or not exists (select 1 from pg_catalog.pg_constraint c
      where c.conrelid = v_profiles and c.contype = 'c'
        and c.conkey = array[(select attnum::smallint from pg_catalog.pg_attribute
          where attrelid = v_profiles and attname = 'merchant_status')]::smallint[]
        and pg_catalog.pg_get_constraintdef(c.oid) like '%pending%approved%suspended%')
  then raise exception 'MERCHANT_REPAIR_PROFILE_POSTFLIGHT_SCHEMA_INVALID'; end if;

  if exists (
    select 1 from (values
      ('id',null::text),('name',null::text),('email',null::text),
      ('role',null::text),('merchant_status','''pending''::text'),
      ('created_at','now()')
    ) expected(column_name,expected_default)
    join pg_catalog.pg_attribute a on a.attrelid = v_profiles
      and a.attname = expected.column_name and a.attnum > 0 and not a.attisdropped
    left join pg_catalog.pg_attrdef d
      on d.adrelid = a.attrelid and d.adnum = a.attnum
    where (expected.expected_default is null and d.oid is not null)
       or (expected.expected_default is not null and
           (d.oid is null or pg_catalog.pg_get_expr(d.adbin,d.adrelid)
             is distinct from expected.expected_default))
  ) or not exists (select 1 from pg_catalog.pg_class c
      where c.oid = v_profiles and c.relrowsecurity)
     or (select count(*) from pg_catalog.pg_policies p
         where p.schemaname = 'public' and p.tablename = 'profiles') <> 3
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Profiles are readable by signed-in users'
         and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.qual like '%id =%' and p.qual like '%auth.uid()%'
         and p.qual like '%is_current_user_admin%')
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Users create their own non-admin profile'
         and p.cmd = 'INSERT' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.with_check like '%id =%' and p.with_check like '%auth.uid()%'
         and p.with_check like '%user%' and p.with_check like '%merchant%'
         and p.with_check not like '%admin%')
     or not exists (select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'profiles'
         and p.policyname = 'Users update their own profile'
         and p.cmd = 'UPDATE' and p.roles = array['authenticated']::name[]
         and p.permissive = 'PERMISSIVE'
         and p.qual like '%id =%' and p.qual like '%auth.uid()%'
         and p.with_check like '%id =%' and p.with_check like '%auth.uid()%') then
    raise exception 'MERCHANT_REPAIR_PROFILE_POSTFLIGHT_CONTRACT_INVALID';
  end if;

  if to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is null
     or to_regprocedure('public.admin_set_merchant_status(uuid,text)') is not null
     or not exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure
         and p.prosecdef and p.proconfig @> array['search_path=""']
         and p.proargnames = array['p_merchant_id','p_status','p_reason']::text[]
         -- p_reason is mandatory: PostgREST must not expose a reason-less
         -- invocation through a defaulted third argument.
         and p.pronargdefaults = 0
         and p.prosrc like '%auth.uid()%' and p.prosrc like '%p.role = ''admin''%'
         and p.prosrc like '%merchant_status_audit%'
          and p.prosrc like '%NOT_AUTHORIZED%'
          and p.prosrc like '%INVALID_MERCHANT_STATUS%'
          and p.prosrc like '%MERCHANT_NOT_FOUND%'
          and p.prosrc like '%INVALID_REASON%'
          and p.prosrc like '%if v_old_status = p_status then return%'
          and p.prosrc like '%REINSTATEMENT_REQUEST_REQUIRED%'
          and p.prosrc like '%INVALID_MERCHANT_STATUS_TRANSITION%'
          and p.prosrc like '%v_old_status = ''pending'' and p_status in (''approved'',''rejected'')%'
          and p.prosrc like '%v_old_status = ''approved'' and p_status = ''suspended''%'
          and p.prosrc like '%actor_id%'
      and p.pronargs = 3 and p.prorettype = 'void'::regtype::oid
     ) or not has_function_privilege('authenticated',
       'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
     or has_function_privilege('anon',
       'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
     or has_function_privilege('service_role',
       'public.admin_set_merchant_status(uuid,text,text)','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_STATUS_RPC_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure
      and p.pronargs = 3 and p.prorettype = 'void'::regtype::oid
      and has_table_privilege(p.proowner,'public.profiles','UPDATE')
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.merchant_status_audit','INSERT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) then raise exception 'MERCHANT_REPAIR_STATUS_DEFINER_PRIVILEGES_INVALID'; end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.admin_list_merchant_notifications()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%p.role = ''admin''%'
      and p.proretset
       and p.proargnames = array[
        'notification_id','merchant_id','merchant_name','merchant_email',
        'merchant_created_at','merchant_status','notification_created_at',
        'resolved_at','resolved_status','read_at'
       ]::text[]
      and p.pronargs = 0
      and p.proallargtypes::oid[] = array[
        'bigint'::regtype::oid,'uuid'::regtype::oid,'text'::regtype::oid,
        'text'::regtype::oid,'timestamp with time zone'::regtype::oid,
        'text'::regtype::oid,'timestamp with time zone'::regtype::oid,
        'timestamp with time zone'::regtype::oid,'text'::regtype::oid,
        'timestamp with time zone'::regtype::oid
      ]::oid[]
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notifications','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notification_reads','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not has_function_privilege('authenticated',
       'public.admin_list_merchant_notifications()','EXECUTE')
     or has_function_privilege('anon',
       'public.admin_list_merchant_notifications()','EXECUTE')
     or has_function_privilege('service_role',
       'public.admin_list_merchant_notifications()','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_RPC_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.admin_unread_merchant_notification_count()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%p.role = ''admin''%'
      and p.prorettype = 'integer'::regtype::oid
      and p.pronargs = 0
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notifications','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notification_reads','SELECT')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not has_function_privilege('authenticated',
       'public.admin_unread_merchant_notification_count()','EXECUTE')
     or has_function_privilege('anon',
       'public.admin_unread_merchant_notification_count()','EXECUTE')
     or has_function_privilege('service_role',
       'public.admin_unread_merchant_notification_count()','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_UNREAD_RPC_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.admin_mark_merchant_notification_read(bigint)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%p.role = ''admin''%'
      and p.proargnames = array['p_notification_id']::text[]
      and p.prorettype = 'void'::regtype::oid
      and p.pronargs = 1
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notifications','SELECT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notification_reads','INSERT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notification_reads','UPDATE')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or not has_function_privilege('authenticated',
       'public.admin_mark_merchant_notification_read(bigint)','EXECUTE')
     or has_function_privilege('anon',
       'public.admin_mark_merchant_notification_read(bigint)','EXECUTE')
     or has_function_privilege('service_role',
       'public.admin_mark_merchant_notification_read(bigint)','EXECUTE') then
    raise exception 'MERCHANT_REPAIR_MARK_READ_RPC_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_sync and p.prosecdef
      and p.prorettype = 'trigger'::regtype::oid
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%on conflict (merchant_id,event_type) do nothing%'
      and p.prosrc like '%resolved_at = coalesce(n.resolved_at,now())%'
      and p.prosrc like '%pending_registration%'
      and has_table_privilege(p.proowner,'public.admin_merchant_notifications','INSERT')
      and has_table_privilege(p.proowner,'public.admin_merchant_notifications','UPDATE')
      and exists (select 1 from pg_catalog.pg_roles r
        where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))
  ) or has_function_privilege('anon',v_sync,'EXECUTE')
    or has_function_privilege('authenticated',v_sync,'EXECUTE')
    or has_function_privilege('service_role',v_sync,'EXECUTE') then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_TRIGGER_FUNCTION_INVALID';
  end if;

  if has_table_privilege('authenticated','public.admin_merchant_notifications','SELECT')
     or has_table_privilege('anon','public.admin_merchant_notifications','SELECT')
     or has_table_privilege('authenticated','public.admin_merchant_notifications','INSERT')
     or has_table_privilege('authenticated','public.admin_merchant_notifications','UPDATE')
     or has_table_privilege('authenticated','public.admin_merchant_notifications','DELETE')
      or has_table_privilege('authenticated','public.admin_merchant_notifications','TRUNCATE')
     or has_table_privilege('anon','public.admin_merchant_notifications','INSERT')
     or has_table_privilege('anon','public.admin_merchant_notifications','UPDATE')
     or has_table_privilege('anon','public.admin_merchant_notifications','DELETE')
      or has_table_privilege('anon','public.admin_merchant_notifications','TRUNCATE')
     or has_table_privilege('authenticated','public.admin_merchant_notification_reads','SELECT')
     or has_table_privilege('authenticated','public.admin_merchant_notification_reads','INSERT')
     or has_table_privilege('authenticated','public.admin_merchant_notification_reads','UPDATE')
     or has_table_privilege('authenticated','public.admin_merchant_notification_reads','DELETE')
      or has_table_privilege('authenticated','public.admin_merchant_notification_reads','TRUNCATE')
     or has_table_privilege('anon','public.admin_merchant_notification_reads','SELECT')
     or has_table_privilege('anon','public.admin_merchant_notification_reads','INSERT')
     or has_table_privilege('anon','public.admin_merchant_notification_reads','UPDATE')
     or has_table_privilege('anon','public.admin_merchant_notification_reads','DELETE')
      or has_table_privilege('anon','public.admin_merchant_notification_reads','TRUNCATE')
      or has_table_privilege('service_role','public.admin_merchant_notifications','SELECT')
      or has_table_privilege('service_role','public.admin_merchant_notifications','INSERT')
      or has_table_privilege('service_role','public.admin_merchant_notifications','UPDATE')
      or has_table_privilege('service_role','public.admin_merchant_notifications','DELETE')
      or has_table_privilege('service_role','public.admin_merchant_notifications','TRUNCATE')
      or has_table_privilege('service_role','public.admin_merchant_notification_reads','SELECT')
      or has_table_privilege('service_role','public.admin_merchant_notification_reads','INSERT')
      or has_table_privilege('service_role','public.admin_merchant_notification_reads','UPDATE')
      or has_table_privilege('service_role','public.admin_merchant_notification_reads','DELETE')
      or has_table_privilege('service_role','public.admin_merchant_notification_reads','TRUNCATE')
      or has_table_privilege('authenticated','public.merchant_status_audit','INSERT')
      or has_table_privilege('authenticated','public.merchant_status_audit','UPDATE')
      or has_table_privilege('authenticated','public.merchant_status_audit','DELETE')
      or has_table_privilege('authenticated','public.merchant_status_audit','TRUNCATE')
      or has_table_privilege('anon','public.merchant_status_audit','SELECT')
      or has_table_privilege('anon','public.merchant_status_audit','INSERT')
      or has_table_privilege('anon','public.merchant_status_audit','UPDATE')
      or has_table_privilege('anon','public.merchant_status_audit','DELETE')
      or has_table_privilege('anon','public.merchant_status_audit','TRUNCATE')
      or has_table_privilege('service_role','public.merchant_status_audit','SELECT')
      or has_table_privilege('service_role','public.merchant_status_audit','INSERT')
      or has_table_privilege('service_role','public.merchant_status_audit','UPDATE')
      or has_table_privilege('service_role','public.merchant_status_audit','DELETE')
      or has_table_privilege('service_role','public.merchant_status_audit','TRUNCATE')
      or not has_table_privilege('authenticated','public.merchant_status_audit','SELECT')
     or not (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.merchant_status_audit'::regclass)
     or not (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.admin_merchant_notifications'::regclass)
     or not (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.admin_merchant_notification_reads'::regclass) then
    raise exception 'MERCHANT_REPAIR_NOTIFICATION_TABLE_SECURITY_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public' and p.tablename = 'merchant_status_audit'
      and p.policyname = 'Admins can view merchant status audit'
      and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[]
      and p.qual like '%is_current_user_admin%'
  ) or not exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public' and p.tablename = 'merchant_status_audit'
      and p.policyname = 'Merchant status audit admin restriction'
       and p.permissive = 'RESTRICTIVE' and p.cmd = 'SELECT'
       and p.roles = array['authenticated']::name[]
      and p.qual like '%is_current_user_admin%'
  ) or not (select relrowsecurity from pg_catalog.pg_class
       where oid = 'public.merchant_status_audit'::regclass)
    then raise exception 'MERCHANT_REPAIR_AUDIT_POLICY_POSTFLIGHT_FAILED'; end if;

  if exists (select 1 from pg_catalog.pg_policies p
      where p.schemaname = 'public'
        and p.tablename in ('admin_merchant_notifications','admin_merchant_notification_reads'))
     or (select count(*) from pg_catalog.pg_policies p
         where p.schemaname = 'public' and p.tablename = 'merchant_status_audit') <> 2 then
    raise exception 'MERCHANT_REPAIR_UNEXPECTED_POLICY_INVENTORY';
  end if;

  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid = v_profiles and not t.tgisinternal) <> 4
     or not exists (
       select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
        and t.tgfoid = v_signup
         and t.tgtype = 7 and t.tgenabled = 'O' and not t.tgisinternal
     ) or not exists (
       select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
         and t.tgname = 'protect_profile_privileged_fields_trigger' and t.tgfoid = v_guard
         and t.tgtype = 19 and t.tgenabled = 'O' and not t.tgisinternal
     ) or not exists (
    select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
      and t.tgname = 'profiles_admin_merchant_notification_insert'
      and t.tgfoid = v_sync and t.tgenabled = 'O' and t.tgtype = 5
      and not t.tgisinternal
  ) or not exists (
    select 1 from pg_catalog.pg_trigger t where t.tgrelid = v_profiles
      and t.tgname = 'profiles_admin_merchant_notification_status'
      and t.tgfoid = v_sync and t.tgenabled = 'O' and t.tgtype = 17
      and cardinality(t.tgattr::smallint[]) = 2
      and t.tgattr::smallint[] @> array[
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = v_profiles and attname = 'role'),
        (select attnum::smallint from pg_catalog.pg_attribute
         where attrelid = v_profiles and attname = 'merchant_status')
      ]::smallint[]
      and not t.tgisinternal
  ) then raise exception 'MERCHANT_REPAIR_NOTIFICATION_TRIGGER_POSTFLIGHT_FAILED'; end if;

  if exists (select 1 from pg_catalog.pg_trigger t
      where t.tgfoid in (v_guard,v_signup,v_sync)
        and t.tgrelid <> v_profiles and not t.tgisinternal)
     or not exists (select 1 from pg_catalog.pg_proc p
       where p.oid = v_signup and has_table_privilege(p.proowner,'auth.users','SELECT')
         and (not (select c.relrowsecurity from pg_catalog.pg_class c
                   where c.oid = 'auth.users'::regclass)
           or exists (select 1 from pg_catalog.pg_roles r
             where r.oid = p.proowner and (r.rolbypassrls or r.rolsuper))))
     or not exists (select 1 from pg_catalog.pg_proc p
       where p.oid = v_sync
         and has_table_privilege(p.proowner,'public.admin_merchant_notifications','INSERT')
         and has_table_privilege(p.proowner,'public.admin_merchant_notifications','UPDATE')) then
    raise exception 'MERCHANT_REPAIR_TRIGGER_DEFINER_PRIVILEGES_INVALID';
  end if;
end;
$postflight$;

commit;
