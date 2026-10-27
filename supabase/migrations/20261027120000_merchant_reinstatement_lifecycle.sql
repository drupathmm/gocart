begin;

-- This migration extends the already-reviewed merchant approval and
-- notification contract. It deliberately fails before DDL when the live
-- schema has not first been reconciled with that contract.
do $preflight$
declare
  v_profiles oid := to_regclass('public.profiles')::oid;
  v_status_rpc oid := to_regprocedure(
    'public.admin_set_merchant_status(uuid,text,text)'
  )::oid;
  v_guard oid := to_regprocedure(
    'public.protect_profile_privileged_fields()'
  )::oid;
begin
  if v_profiles is null
     or to_regclass('public.products') is null
     or to_regclass('public.cart_items') is null
     or to_regclass('public.order_items') is null
     or to_regclass('public.merchant_status_audit') is null
     or to_regclass('public.admin_merchant_notifications') is null
     or to_regclass('public.admin_merchant_notification_reads') is null then
    raise exception 'MERCHANT_LIFECYCLE_REQUIRES_APPROVAL_REPAIR_CONTRACT';
  end if;

  if to_regprocedure('auth.uid()') is null
     or to_regprocedure('auth.role()') is null
     or to_regprocedure('public.is_current_user_admin()') is null
     or v_status_rpc is null
     or to_regprocedure('public.admin_list_merchant_notifications()') is null
     or to_regprocedure('public.admin_unread_merchant_notification_count()') is null
     or to_regprocedure('public.admin_mark_merchant_notification_read(bigint)') is null then
    raise exception 'MERCHANT_LIFECYCLE_REQUIRED_RPC_MISSING';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'admin_set_merchant_status') <> 1
     or (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'protect_profile_privileged_fields') <> 1 then
    raise exception 'MERCHANT_LIFECYCLE_UNEXPECTED_FUNCTION_OVERLOAD';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_status_rpc and p.prorettype = 'void'::regtype::oid
      and p.proargnames = array['p_merchant_id','p_status','p_reason']::text[]
      and p.pronargdefaults = 0 and p.prosecdef
      and p.proconfig @> array['search_path=""']
      and has_table_privilege(p.proowner,'public.profiles','SELECT')
      and has_table_privilege(p.proowner,'public.profiles','UPDATE')
      and has_table_privilege(p.proowner,'public.merchant_status_audit','INSERT')
  ) then
    raise exception 'MERCHANT_LIFECYCLE_STATUS_RPC_CONTRACT_INVALID';
  end if;

  if v_guard is null or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = v_guard and p.prorettype = 'trigger'::regtype::oid
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%auth.uid()%'
      and p.prosrc like '%auth.role()%'
      and p.prosrc not like '%app.merchant_auto_approval%'
  ) then
    raise exception 'MERCHANT_LIFECYCLE_PROFILE_GUARD_NOT_HARDENED';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = v_profiles and t.tgfoid = v_guard
      and t.tgenabled = 'O' and not t.tgisinternal
      and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
  ) then
    raise exception 'MERCHANT_LIFECYCLE_PROFILE_GUARD_TRIGGER_MISSING';
  end if;

  -- This lifecycle extension follows the legacy-compatible security draft,
  -- whose boolean-only helper and trigger locals intentionally have these
  -- names. Do not require the unrelated historical helper contract.
  if to_regprocedure('gocart_private.product_visible_to_requester(uuid)') is null
     or to_regprocedure('public.guard_active_merchant_cart_item()') is null
     or to_regprocedure('public.guard_active_merchant_order_item()') is null
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.cart_items'::regclass
         and t.tgname = 'cart_items_require_approved_merchant_insert'
         and t.tgfoid = 'public.guard_active_merchant_cart_item()'::regprocedure
         and t.tgenabled = 'O' and not t.tgisinternal
     )
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.cart_items'::regclass
         and t.tgname = 'cart_items_require_approved_merchant_update'
         and t.tgfoid = 'public.guard_active_merchant_cart_item()'::regprocedure
         and t.tgenabled = 'O' and not t.tgisinternal
     )
     or not exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'public.order_items'::regclass
         and t.tgname = 'order_items_require_approved_merchant'
         and t.tgfoid = 'public.guard_active_merchant_order_item()'::regprocedure
         and t.tgenabled = 'O' and not t.tgisinternal
     ) then
    raise exception 'MERCHANT_LIFECYCLE_PRODUCT_PURCHASE_GUARD_MISSING';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'gocart_private.product_visible_to_requester(uuid)'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%p.merchant_status = ''approved''%'
      and p.prosrc like '%auth.uid()%'
      and has_function_privilege('anon',p.oid,'EXECUTE')
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('service_role',p.oid,'EXECUTE')
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.guard_active_merchant_cart_item()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%v_status is distinct from ''approved''%'
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.guard_active_merchant_order_item()'::regprocedure
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and p.prosrc like '%v_status is distinct from ''approved''%'
  ) then
    raise exception 'MERCHANT_LIFECYCLE_PRODUCT_GUARD_CONTRACT_INVALID';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public' and p.tablename = 'products'
      and p.policyname = 'Merchant approval required for product reads'
      and p.permissive = 'RESTRICTIVE'
      and p.cmd = 'SELECT'
      and p.qual like '%gocart_private.product_visible_to_requester%'
  ) then
    raise exception 'MERCHANT_LIFECYCLE_PRODUCT_VISIBILITY_POLICY_MISSING';
  end if;

  if has_column_privilege('anon','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('authenticated','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('service_role','public.profiles','merchant_status','UPDATE')
     or has_column_privilege('authenticated','public.profiles','role','UPDATE') then
    raise exception 'MERCHANT_LIFECYCLE_PROFILE_COLUMN_PRIVILEGE_UNSAFE';
  end if;

  if exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.profiles'::regclass and not c.relrowsecurity
  ) or exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.products'::regclass and not c.relrowsecurity
  ) then
    raise exception 'MERCHANT_LIFECYCLE_REQUIRED_RLS_DISABLED';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in (
          'merchant_request_reinstatement',
          'merchant_get_reinstatement_request',
          'admin_list_merchant_reinstatement_requests',
          'admin_resolve_merchant_reinstatement',
          'admin_merchant_lifecycle_counts'
        )) <> 0
     or to_regclass('public.merchant_reinstatement_requests') is not null then
    raise exception 'MERCHANT_LIFECYCLE_OBJECT_ALREADY_EXISTS_REVIEW_REQUIRED';
  end if;
end;
$preflight$;

create table public.merchant_reinstatement_requests (
  id bigint generated always as identity primary key,
  merchant_id uuid not null references public.profiles(id) on delete restrict,
  request_message text not null
    check (length(btrim(request_message)) between 1 and 2000),
  request_status text not null default 'open'
    check (request_status in ('open','approved','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete restrict,
  resolution_reason text check (
    resolution_reason is null or length(btrim(resolution_reason)) between 1 and 500
  ),
  constraint merchant_reinstatement_resolution_consistent check (
    (request_status = 'open' and resolved_at is null and resolved_by is null
      and resolution_reason is null)
    or
    (request_status in ('approved','rejected') and resolved_at is not null
      and resolved_by is not null)
  )
);

create unique index merchant_reinstatement_one_open_per_merchant_idx
  on public.merchant_reinstatement_requests (merchant_id)
  where request_status = 'open';
create index merchant_reinstatement_review_queue_idx
  on public.merchant_reinstatement_requests (created_at desc)
  where request_status = 'open';

alter table public.merchant_reinstatement_requests enable row level security;
revoke all privileges on table public.merchant_reinstatement_requests
  from public, anon, authenticated, service_role;

-- Normal merchant status operations cannot restore a suspended merchant.
-- That transition is only available through an open, admin-reviewed request.
create or replace function public.admin_set_merchant_status(
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
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  if v_actor_id is null or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_actor_id and p.role = 'admin'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_status is null or p_status not in ('approved','suspended','rejected') then
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
  if v_old_status = p_status then return; end if;
  if v_old_status = 'suspended' and p_status = 'approved' then
    raise exception 'REINSTATEMENT_REQUEST_REQUIRED';
  end if;
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

-- Register one open request per suspended merchant. The profile lock makes
-- request creation serialize with an administrator's status transition.
create function public.merchant_request_reinstatement(p_message text)
returns table (
  request_id bigint,
  request_status text,
  request_message text,
  created_at timestamptz,
  resolved_at timestamptz,
  resolution_reason text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_merchant_id uuid := (select auth.uid());
  v_role text;
  v_status text;
  v_request_id bigint;
begin
  if v_merchant_id is null or (select auth.role()) is distinct from 'authenticated' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_message is null or length(btrim(p_message)) not between 1 and 2000 then
    raise exception 'INVALID_REINSTATEMENT_MESSAGE';
  end if;

  select p.role,p.merchant_status into v_role,v_status
  from public.profiles p where p.id = v_merchant_id for update;
  if not found or v_role is distinct from 'merchant' then
    raise exception 'NOT_MERCHANT';
  end if;
  if v_status is distinct from 'suspended' then
    raise exception 'MERCHANT_NOT_SUSPENDED';
  end if;

  insert into public.merchant_reinstatement_requests
    (merchant_id,request_message)
  values (v_merchant_id,btrim(p_message))
  on conflict (merchant_id) where request_status = 'open' do nothing
  returning id into v_request_id;

  if v_request_id is null then
    select r.id into v_request_id
    from public.merchant_reinstatement_requests r
    where r.merchant_id = v_merchant_id and r.request_status = 'open'
    for update;
  end if;

  return query
  select r.id,r.request_status,r.request_message,r.created_at,
         r.resolved_at,r.resolution_reason
  from public.merchant_reinstatement_requests r where r.id = v_request_id;
end;
$function$;

create function public.merchant_get_reinstatement_request()
returns table (
  request_id bigint,
  request_status text,
  request_message text,
  created_at timestamptz,
  resolved_at timestamptz,
  resolution_reason text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_merchant_id uuid := (select auth.uid());
begin
  if v_merchant_id is null or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_merchant_id and p.role = 'merchant'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
  select r.id,r.request_status,r.request_message,r.created_at,
         r.resolved_at,r.resolution_reason
  from public.merchant_reinstatement_requests r
  where r.merchant_id = v_merchant_id
  order by r.created_at desc,r.id desc limit 1;
end;
$function$;

create function public.admin_list_merchant_reinstatement_requests()
returns table (
  request_id bigint,
  merchant_id uuid,
  merchant_name text,
  merchant_email text,
  request_message text,
  request_created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
begin
  if v_admin_id is null or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_admin_id and p.role = 'admin'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
  select r.id,p.id,p.name,p.email,r.request_message,r.created_at
  from public.merchant_reinstatement_requests r
  join public.profiles p on p.id = r.merchant_id
  where r.request_status = 'open' and p.role = 'merchant'
    and p.merchant_status = 'suspended'
  order by r.created_at asc,r.id asc;
end;
$function$;

-- Counts come from profiles and open requests, never notification read state.
create function public.admin_merchant_lifecycle_counts()
returns table (
  pending_merchants bigint,
  approved_merchants bigint,
  suspended_merchants bigint,
  rejected_merchants bigint,
  open_reinstatement_requests bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
begin
  if v_admin_id is null or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_admin_id and p.role = 'admin'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  return query
  select count(*) filter (where p.merchant_status = 'pending'),
         count(*) filter (where p.merchant_status = 'approved'),
         count(*) filter (where p.merchant_status = 'suspended'),
         count(*) filter (where p.merchant_status = 'rejected'),
         (select count(*) from public.merchant_reinstatement_requests r
          where r.request_status = 'open')
  from public.profiles p where p.role = 'merchant';
end;
$function$;

-- Resolve under locks in the same order as request submission and status
-- changes: profile first, then request. Approval, audit, and resolution commit
-- atomically; rejection leaves the merchant suspended.
create function public.admin_resolve_merchant_reinstatement(
  p_request_id bigint,
  p_decision text,
  p_reason text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_id uuid := (select auth.uid());
  v_merchant_id uuid;
  v_role text;
  v_merchant_status text;
  v_request_status text;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  if v_admin_id is null or (select auth.role()) is distinct from 'authenticated'
     or not exists (
       select 1 from public.profiles p
       where p.id = v_admin_id and p.role = 'admin'
     ) then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_decision not in ('approved','rejected') then
    raise exception 'INVALID_REINSTATEMENT_DECISION';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'INVALID_REASON';
  end if;

  select r.merchant_id into v_merchant_id
  from public.merchant_reinstatement_requests r where r.id = p_request_id;
  if not found then raise exception 'REINSTATEMENT_REQUEST_NOT_FOUND'; end if;

  select p.role,p.merchant_status into v_role,v_merchant_status
  from public.profiles p where p.id = v_merchant_id for update;
  if not found or v_role is distinct from 'merchant' then
    raise exception 'MERCHANT_NOT_FOUND';
  end if;

  select r.request_status into v_request_status
  from public.merchant_reinstatement_requests r
  where r.id = p_request_id and r.merchant_id = v_merchant_id
  for update;
  if not found then raise exception 'REINSTATEMENT_REQUEST_NOT_FOUND'; end if;
  if v_request_status <> 'open' then
    if v_request_status = p_decision then return v_request_status; end if;
    raise exception 'REINSTATEMENT_REQUEST_ALREADY_RESOLVED';
  end if;
  if v_merchant_status is distinct from 'suspended' then
    raise exception 'MERCHANT_NOT_SUSPENDED';
  end if;

  if p_decision = 'approved' then
    update public.profiles p set merchant_status = 'approved'
    where p.id = v_merchant_id and p.role = 'merchant';
    insert into public.merchant_status_audit
      (merchant_id,actor_id,old_status,new_status,reason)
    values (
      v_merchant_id,v_admin_id,'suspended','approved',v_reason
    );
  end if;

  update public.merchant_reinstatement_requests r
  set request_status = p_decision,
      resolved_at = now(),
      resolved_by = v_admin_id,
      resolution_reason = v_reason
  where r.id = p_request_id and r.request_status = 'open';
  if not found then raise exception 'REINSTATEMENT_REQUEST_ALREADY_RESOLVED'; end if;
  return p_decision;
end;
$function$;

revoke all on function public.admin_set_merchant_status(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.merchant_request_reinstatement(text)
  from public,anon,authenticated,service_role;
revoke all on function public.merchant_get_reinstatement_request()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_list_merchant_reinstatement_requests()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_merchant_lifecycle_counts()
  from public,anon,authenticated,service_role;
revoke all on function public.admin_resolve_merchant_reinstatement(bigint,text,text)
  from public,anon,authenticated,service_role;

grant execute on function public.admin_set_merchant_status(uuid,text,text)
  to authenticated;
grant execute on function public.merchant_request_reinstatement(text)
  to authenticated;
grant execute on function public.merchant_get_reinstatement_request()
  to authenticated;
grant execute on function public.admin_list_merchant_reinstatement_requests()
  to authenticated;
grant execute on function public.admin_merchant_lifecycle_counts()
  to authenticated;
grant execute on function public.admin_resolve_merchant_reinstatement(bigint,text,text)
  to authenticated;

do $postflight$
declare
  v_table oid := 'public.merchant_reinstatement_requests'::regclass::oid;
  v_function record;
begin
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = v_table and c.relrowsecurity
  ) or has_table_privilege('anon',v_table,'SELECT')
    or has_table_privilege('authenticated',v_table,'SELECT')
    or has_table_privilege('anon',v_table,'INSERT')
    or has_table_privilege('authenticated',v_table,'INSERT')
    or has_table_privilege('anon',v_table,'UPDATE')
    or has_table_privilege('authenticated',v_table,'UPDATE') then
    raise exception 'MERCHANT_REINSTATEMENT_TABLE_ACCESS_INVALID';
  end if;

  if (select count(*) from pg_catalog.pg_constraint c
      where c.conrelid = v_table and c.contype = 'p') <> 1
     or not exists (
       select 1 from pg_catalog.pg_index i
       where i.indrelid = v_table and i.indisunique and i.indisvalid
         and i.indpred is not null
         and pg_catalog.pg_get_indexdef(i.indexrelid) like '%(merchant_id)%'
         and pg_catalog.pg_get_expr(i.indpred,i.indrelid) like '%open%'
     )
     or not exists (
       select 1 from pg_catalog.pg_constraint c
       where c.conrelid = v_table and c.conname = 'merchant_reinstatement_resolution_consistent'
         and c.contype = 'c' and c.convalidated
     ) then
    raise exception 'MERCHANT_REINSTATEMENT_CONSTRAINTS_INVALID';
  end if;

  for v_function in
    select p.oid,p.proname,p.proowner
    from pg_catalog.pg_proc p
    where p.oid in (
      'public.admin_set_merchant_status(uuid,text,text)'::regprocedure,
      'public.merchant_request_reinstatement(text)'::regprocedure,
      'public.merchant_get_reinstatement_request()'::regprocedure,
      'public.admin_list_merchant_reinstatement_requests()'::regprocedure,
      'public.admin_merchant_lifecycle_counts()'::regprocedure,
      'public.admin_resolve_merchant_reinstatement(bigint,text,text)'::regprocedure
    )
  loop
    if not (select p.prosecdef and p.proconfig @> array['search_path=""']
            from pg_catalog.pg_proc p where p.oid = v_function.oid)
       or not has_function_privilege('authenticated',v_function.oid,'EXECUTE')
       or has_function_privilege('anon',v_function.oid,'EXECUTE')
       or has_function_privilege('service_role',v_function.oid,'EXECUTE')
       or not has_table_privilege(v_function.proowner,'public.profiles','SELECT') then
      raise exception 'MERCHANT_LIFECYCLE_FUNCTION_SECURITY_INVALID: %',v_function.proname;
    end if;
  end loop;

  if not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.merchant_request_reinstatement(text)'::regprocedure),
       'public.merchant_reinstatement_requests','INSERT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.merchant_request_reinstatement(text)'::regprocedure),
       'public.merchant_reinstatement_requests','SELECT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.merchant_request_reinstatement(text)'::regprocedure),
       'public.profiles','UPDATE')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.merchant_get_reinstatement_request()'::regprocedure),
       'public.merchant_reinstatement_requests','SELECT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_list_merchant_reinstatement_requests()'::regprocedure),
       'public.merchant_reinstatement_requests','SELECT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_merchant_lifecycle_counts()'::regprocedure),
       'public.merchant_reinstatement_requests','SELECT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_resolve_merchant_reinstatement(bigint,text,text)'::regprocedure),
       'public.merchant_reinstatement_requests','UPDATE')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_resolve_merchant_reinstatement(bigint,text,text)'::regprocedure),
       'public.merchant_reinstatement_requests','SELECT')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_resolve_merchant_reinstatement(bigint,text,text)'::regprocedure),
       'public.profiles','UPDATE')
     or not has_table_privilege(
       (select p.proowner from pg_catalog.pg_proc p
        where p.oid = 'public.admin_resolve_merchant_reinstatement(bigint,text,text)'::regprocedure),
       'public.merchant_status_audit','INSERT') then
    raise exception 'MERCHANT_LIFECYCLE_FUNCTION_OWNER_PRIVILEGES_INVALID';
  end if;

  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname in (
          'merchant_request_reinstatement','merchant_get_reinstatement_request',
          'admin_list_merchant_reinstatement_requests','admin_merchant_lifecycle_counts',
          'admin_resolve_merchant_reinstatement'
        )) <> 5 then
    raise exception 'MERCHANT_LIFECYCLE_RPC_OVERLOAD_MISMATCH';
  end if;
end;
$postflight$;

commit;
