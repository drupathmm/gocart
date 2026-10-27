-- Forward-only merchant authorization repair for the verified legacy GoCart
-- schema. This is intentionally kept in supabase/drafts: the live migration
-- history is empty, and replaying the historical chain is unsafe. Do not run
-- this until an owner-approved restored GoCart baseline has passed its tests.
-- This migration does not touch products, carts, orders, order items, stock,
-- payment state, login, or reinstatement-request data.

begin;

do $preflight$
declare
  v_profiles oid := to_regclass('public.profiles')::oid;
  v_approve oid := to_regprocedure(
    'public.approve_my_merchant_account()'
  )::oid;
  v_legacy_status oid := to_regprocedure(
    'public.admin_set_merchant_status(uuid,text)'
  )::oid;
  v_profile_guard oid := to_regprocedure(
    'public.protect_profile_privileged_fields()'
  )::oid;
  v_signup oid := to_regprocedure(
    'public.set_initial_profile_status()'
  )::oid;
begin
  if v_profiles is null
     or to_regprocedure('auth.uid()') is null
     or to_regprocedure('auth.role()') is null then
    raise exception 'MERCHANT_AUTH_REQUIRED_LEGACY_OBJECT_MISSING';
  end if;

  if exists (
    select required.column_name
    from (values
      ('id','uuid'),('email','text'),('role','text'),
      ('merchant_status','text'),('created_at','timestamp with time zone')
    )
      as required(column_name, type_name)
    where not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid = v_profiles
        and a.attname = required.column_name
        and a.attnum > 0 and not a.attisdropped
        and pg_catalog.format_type(a.atttypid,a.atttypmod) = required.type_name
    )
  ) then
    raise exception 'MERCHANT_AUTH_PROFILE_SCHEMA_MISMATCH';
  end if;

  if exists (
    select 1 from public.profiles p
    where p.role = 'merchant'
      and (p.merchant_status is null
        or p.merchant_status not in ('pending','approved','suspended'))
  ) then
    raise exception 'MERCHANT_AUTH_INVALID_EXISTING_STATUS';
  end if;

  -- The repository's only client profile edit is name. Stop if the live ACL
  -- also permits other ordinary profile edits, so this repair cannot silently
  -- remove an unreviewed legitimate workflow when it narrows UPDATE grants.
  if exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = v_profiles and a.attnum > 0 and not a.attisdropped
      and a.attname not in ('id','email','role','merchant_status','created_at','name')
      and (
        has_column_privilege('anon',v_profiles,a.attname,'UPDATE')
        or has_column_privilege('authenticated',v_profiles,a.attname,'UPDATE')
        or has_column_privilege('service_role',v_profiles,a.attname,'UPDATE')
      )
  ) then
    raise exception 'MERCHANT_AUTH_PROFILE_UPDATE_GRANTS_REQUIRE_REVIEW';
  end if;

  if v_approve is null
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'approve_my_merchant_account') <> 1 then
    raise exception 'MERCHANT_AUTH_SELF_APPROVAL_CONTRACT_MISMATCH';
  end if;
  if v_legacy_status is null
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_set_merchant_status') <> 1 then
    raise exception 'MERCHANT_AUTH_ADMIN_RPC_CONTRACT_MISMATCH';
  end if;

  if v_profile_guard is null or v_signup is null
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = v_profiles and t.tgfoid = v_profile_guard
         and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
         and t.tgenabled = 'O' and not t.tgisinternal
     )
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = v_profiles and t.tgfoid = v_signup
         and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4
         and t.tgenabled = 'O' and not t.tgisinternal
     ) then
    raise exception 'MERCHANT_AUTH_PROFILE_TRIGGER_BINDING_MISMATCH';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_signup and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and p.prosrc like '%new.merchant_status := ''pending''%'
  ) then
    raise exception 'MERCHANT_AUTH_SIGNUP_NOT_PENDING';
  end if;

  -- This repair expects the audit table to be absent in the legacy baseline.
  -- If another writer has installed one, stop for schema review rather than
  -- guessing whether its columns, policies, or historical rows are reusable.
  if to_regclass('public.merchant_status_audit') is not null then
    raise exception 'MERCHANT_AUTH_AUDIT_OBJECT_EXISTS_REVIEW_REQUIRED';
  end if;

  -- PL/pgSQL body references are not all tracked as catalog dependencies.
  -- Permit only the known RPC and profile guard to contain the legacy setting.
  if exists (
    select 1 from pg_catalog.pg_proc p
    where p.prosrc like '%app.merchant_auto_approval%'
      and p.oid not in (v_approve,v_profile_guard)
  ) then
    raise exception 'MERCHANT_AUTH_UNEXPECTED_APPROVAL_CONTEXT_DEPENDENCY';
  end if;
end;
$preflight$;

-- No foreign keys are used for actor/merchant IDs so audit evidence survives
-- later profile deletion. The identifiers still refer to profiles/auth users
-- at the time the decision is recorded.
create table public.merchant_status_audit (
  id bigint generated always as identity primary key,
  merchant_id uuid not null,
  actor_id uuid not null,
  old_status text not null
    check (old_status in ('pending','approved','suspended')),
  new_status text not null
    check (new_status in ('approved','suspended')),
  reason text not null
    check (length(btrim(reason)) between 1 and 500),
  changed_at timestamptz not null default clock_timestamp()
);

create index merchant_status_audit_merchant_changed_idx
  on public.merchant_status_audit (merchant_id,changed_at desc,id desc);
create index merchant_status_audit_actor_changed_idx
  on public.merchant_status_audit (actor_id,changed_at desc,id desc);

alter table public.merchant_status_audit enable row level security;
revoke all privileges on table public.merchant_status_audit
  from public,anon,authenticated,service_role;
grant select on table public.merchant_status_audit to authenticated;
create policy merchant_status_audit_admin_read
  on public.merchant_status_audit for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid()) and p.role = 'admin'
    )
  );

-- Ordinary profile writes cannot change identity, role, or status. Status
-- writes through SECURITY DEFINER RPCs remain attributable to the original
-- authenticated admin identity; custom GUCs are never accepted as proof.
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
     and (new.role is null or new.role not in ('user','merchant','admin')) then
    raise exception using
      errcode = '23514',
      message = 'PROFILE_INVALID_ROLE';
  end if;

  -- Role changes have no supported application workflow. Even an admin must
  -- use a separate reviewed operation rather than updating profiles directly.
  if new.role is distinct from old.role then
    raise exception using
      errcode = '42501',
      message = 'PROFILE_ROLE_CHANGE_DENIED';
  end if;

  if new.merchant_status is distinct from old.merchant_status
     and (not v_is_authenticated_admin
       or old.role is distinct from 'merchant'
       or new.role is distinct from 'merchant'
       or new.merchant_status is null
       or new.merchant_status not in ('pending','approved','suspended')) then
    raise exception using
      errcode = '42501',
      message = 'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED';
  end if;

  return new;
end;
$function$;
revoke all on function public.protect_profile_privileged_fields()
  from public,anon,authenticated,service_role;

-- Preserve name editing and the existing pending-on-signup insert contract.
revoke update on table public.profiles
  from public,anon,authenticated,service_role;
revoke update (id,name,email,role,created_at,merchant_status)
  on table public.profiles from public,anon,authenticated,service_role;
grant update (name) on table public.profiles to authenticated;

-- RESTRICT is intentional: any tracked dependency blocks removal for review.
revoke all on function public.approve_my_merchant_account()
  from public,anon,authenticated,service_role;
drop function public.approve_my_merchant_account() restrict;

revoke all on function public.admin_set_merchant_status(uuid,text)
  from public,anon,authenticated,service_role;
drop function public.admin_set_merchant_status(uuid,text) restrict;

-- There is exactly one reason-aware overload and no defaulted parameter, so
-- PostgREST callers cannot omit the reason or ambiguously resolve signatures.
create function public.admin_set_merchant_status(
  p_merchant_id uuid,
  p_status text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_old_status text;
  v_reason text := nullif(btrim(p_reason),'');
begin
  if v_actor_id is null
     or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_actor_id and p.role = 'admin'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_merchant_id is null then raise exception 'MERCHANT_NOT_FOUND'; end if;
  if p_status is null or p_status not in ('approved','suspended') then
    raise exception 'INVALID_MERCHANT_STATUS';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  select p.merchant_status into v_old_status
  from public.profiles p
  where p.id = p_merchant_id and p.role = 'merchant'
  for update;
  if not found then raise exception 'MERCHANT_NOT_FOUND'; end if;
  if v_old_status is null then raise exception 'MERCHANT_STATUS_INVALID'; end if;
  if v_old_status = p_status then return; end if;

  if v_old_status = 'suspended' and p_status = 'approved' then
    raise exception 'REINSTATEMENT_REQUEST_REQUIRED';
  end if;
  if not ((v_old_status = 'pending' and p_status = 'approved')
       or (v_old_status = 'approved' and p_status = 'suspended')) then
    raise exception 'INVALID_MERCHANT_STATUS_TRANSITION';
  end if;

  update public.profiles p set merchant_status = p_status
  where p.id = p_merchant_id and p.role = 'merchant';
  if not found then raise exception 'MERCHANT_NOT_FOUND'; end if;

  insert into public.merchant_status_audit (
    merchant_id,actor_id,old_status,new_status,reason
  ) values (
    p_merchant_id,v_actor_id,v_old_status,p_status,v_reason
  );
end;
$function$;

revoke all on function public.admin_set_merchant_status(uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_set_merchant_status(uuid,text,text)
  to authenticated;

do $postflight$
declare
  v_status_rpc oid := to_regprocedure(
    'public.admin_set_merchant_status(uuid,text,text)'
  )::oid;
begin
  if to_regprocedure('public.approve_my_merchant_account()') is not null
     or (select count(*) from pg_catalog.pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'admin_set_merchant_status') <> 1
     or v_status_rpc is null then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_RPC_MISMATCH';
  end if;

  if has_function_privilege('anon',v_status_rpc,'EXECUTE')
     or not has_function_privilege('authenticated',v_status_rpc,'EXECUTE')
     or has_function_privilege('service_role',v_status_rpc,'EXECUTE')
     or exists (
       select 1 from pg_catalog.aclexplode(
         coalesce((select p.proacl from pg_catalog.pg_proc p where p.oid=v_status_rpc),
                  pg_catalog.acldefault('f',(select p.proowner from pg_catalog.pg_proc p where p.oid=v_status_rpc)))
       ) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     ) then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_GRANTS_INVALID';
  end if;

  if has_column_privilege('anon','public.profiles','role','UPDATE')
     or has_column_privilege('authenticated','public.profiles','role','UPDATE')
     or has_column_privilege('service_role','public.profiles','role','UPDATE')
     or has_column_privilege('anon','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('authenticated','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('service_role','public.profiles','merchant_status','UPDATE') then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_PROFILE_GRANTS_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.protect_profile_privileged_fields()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and p.prosrc like '%auth.uid()%'
      and p.prosrc not like '%app.merchant_auto_approval%'
  ) then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_PROFILE_GUARD_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.merchant_status_audit'::regclass
      and c.relrowsecurity
  ) then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_AUDIT_RLS_DISABLED';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_status_rpc
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.profiles','UPDATE')
      and has_table_privilege(p.proowner,'public.merchant_status_audit','INSERT')
  ) then
    raise exception 'MERCHANT_AUTH_POSTFLIGHT_DEFINER_PRIVILEGES_INVALID';
  end if;
end;
$postflight$;

commit;
