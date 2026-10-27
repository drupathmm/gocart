-- Run only after the legacy authorization draft is applied to an
-- owner-approved restored GoCart baseline. This test rolls back its fixtures.
begin;

select plan(32);

select ok(
  to_regprocedure('public.approve_my_merchant_account()') is null,
  'the self-approval RPC is absent'
);
select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_set_merchant_status'
     and p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure),
  'only the reason-aware admin status RPC exists'
);
select ok(
  (select p.proargnames = array['p_merchant_id','p_status','p_reason']::text[]
          and p.pronargdefaults = 0 and p.prosecdef
          and p.proconfig @> array['search_path=""']
   from pg_catalog.pg_proc p
   where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure),
  'admin RPC has exact arguments, no default reason, SECURITY DEFINER and empty search_path'
);
select ok(
  has_function_privilege('authenticated',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
  and not has_function_privilege('anon',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
  and not has_function_privilege('service_role',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE'),
  'admin RPC execution is limited to authenticated callers and checks admin identity internally'
);
select ok(
  not exists (
    select 1 from pg_catalog.aclexplode(
      coalesce((select p.proacl from pg_catalog.pg_proc p
                where p.oid='public.admin_set_merchant_status(uuid,text,text)'::regprocedure),
               pg_catalog.acldefault('f',(select p.proowner from pg_catalog.pg_proc p
                where p.oid='public.admin_set_merchant_status(uuid,text,text)'::regprocedure)))
    ) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no inherited execute grant on the admin RPC'
);
select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=""']
          and p.prosrc not like '%app.merchant_auto_approval%'
   from pg_catalog.pg_proc p
   where p.oid='public.protect_profile_privileged_fields()'::regprocedure),
  'profile guard is hardened and does not trust the legacy custom setting'
);
select ok(
  exists (select 1 from pg_catalog.pg_trigger t
          where t.tgrelid='public.profiles'::regclass
            and t.tgfoid='public.protect_profile_privileged_fields()'::regprocedure
            and t.tgenabled='O' and not t.tgisinternal),
  'the hardened profile guard remains attached and enabled'
);
select ok(
  (select c.relrowsecurity from pg_catalog.pg_class c
   where c.oid='public.merchant_status_audit'::regclass)
  and has_table_privilege('authenticated','public.merchant_status_audit','SELECT')
  and not has_table_privilege('authenticated','public.merchant_status_audit','INSERT')
  and not has_table_privilege('anon','public.merchant_status_audit','SELECT'),
  'audit table uses RLS and denies direct client writes'
);
select ok(
  exists (select 1 from pg_catalog.pg_policies p
          where p.schemaname='public' and p.tablename='merchant_status_audit'
            and p.policyname='merchant_status_audit_admin_read'),
  'audit reads are governed by the admin-only policy'
);
select ok(
  not has_column_privilege('authenticated','public.profiles','role','UPDATE')
  and not has_column_privilege('authenticated','public.profiles','merchant_status','UPDATE')
  and not has_column_privilege('anon','public.profiles','merchant_status','UPDATE')
  and not has_column_privilege('service_role','public.profiles','merchant_status','UPDATE'),
  'client roles cannot directly update privileged profile fields'
);

select set_config('request.jwt.claim.role','',true);
select set_config('request.jwt.claim.sub','',true);
insert into auth.users (id,email) values
  ('a9000000-0000-0000-0000-000000000001','legacy-admin@example.invalid'),
  ('a9000000-0000-0000-0000-000000000002','legacy-customer@example.invalid'),
  ('a9000000-0000-0000-0000-000000000003','legacy-merchant@example.invalid');
insert into public.profiles (id,name,email,role) values
  ('a9000000-0000-0000-0000-000000000001','Legacy Test Admin','ignored','admin'),
  ('a9000000-0000-0000-0000-000000000002','Legacy Test Customer','ignored','user');
-- Temporary grant lets the test exercise the trigger despite the production
-- column revocation; the enclosing transaction rolls it back.
grant update (merchant_status) on public.profiles to authenticated;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a9000000-0000-0000-0000-000000000003',true);
select set_config('app.merchant_auto_approval','true',true);
set local role authenticated;
select lives_ok(
  $$insert into public.profiles(id,name,email,role)
    values ('a9000000-0000-0000-0000-000000000003','Legacy Test Merchant',
      'spoofed@example.invalid','merchant')$$,
  'merchant signup can still create its own profile'
);
select is(
  (select merchant_status from public.profiles
   where id='a9000000-0000-0000-0000-000000000003'),
  'pending','new merchant signup remains pending'
);
select throws_ok(
  $$select public.approve_my_merchant_account()$$,
  '42883',null,'authenticated merchant cannot invoke the removed self-approval RPC'
);
select throws_ok(
  $$update public.profiles set merchant_status='approved'
    where id='a9000000-0000-0000-0000-000000000003'$$,
  '42501','PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED',
  'legacy approval setting cannot authorize direct merchant status updates'
);
select throws_ok(
  $$update public.profiles set role='admin'
    where id='a9000000-0000-0000-0000-000000000003'$$,
  '42501',null,'authenticated merchant cannot directly update role'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved','Attempt')$$,
  'P0001','NOT_AUTHORIZED','ordinary merchant cannot call the admin operation'
);
reset role;
revoke update (merchant_status) on public.profiles from authenticated;

select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved','Attempt')$$,
  '42501',null,'anonymous caller cannot execute the admin operation'
);
reset role;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a9000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','suspended','Unauthorized')$$,
  'P0001','NOT_AUTHORIZED','ordinary customer cannot suspend a merchant'
);
reset role;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a9000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','suspended','Skip approval')$$,
  'P0001','INVALID_MERCHANT_STATUS_TRANSITION',
  'admin cannot suspend a pending merchant without first approving'
);
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved','Documents verified')$$,
  'admin can approve a pending merchant with a reason'
);
select is(
  (select merchant_status from public.profiles
   where id='a9000000-0000-0000-0000-000000000003'),
  'approved','approval changes the merchant state'
);
select ok(
  exists (select 1 from public.merchant_status_audit a
          where a.merchant_id='a9000000-0000-0000-0000-000000000003'
            and a.actor_id='a9000000-0000-0000-0000-000000000001'
            and a.old_status='pending' and a.new_status='approved'
            and a.reason='Documents verified' and a.changed_at <= clock_timestamp()),
  'approval audit records actor, target, old/new status, reason and timestamp'
);
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','suspended','Policy violation')$$,
  'admin can suspend an approved merchant with a reason'
);
select ok(
  exists (select 1 from public.merchant_status_audit a
          where a.merchant_id='a9000000-0000-0000-0000-000000000003'
            and a.actor_id='a9000000-0000-0000-0000-000000000001'
            and a.old_status='approved' and a.new_status='suspended'
            and a.reason='Policy violation' and a.changed_at <= clock_timestamp()),
  'suspension audit records actor, target, transition, reason and timestamp'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved','   ')$$,
  'P0001','INVALID_REASON','blank reasons are rejected'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved',null)$$,
  'P0001','INVALID_REASON','null reasons are rejected'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','pending','Invalid target')$$,
  'P0001','INVALID_MERCHANT_STATUS','invalid status values are rejected'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000099','approved','Missing')$$,
  'P0001','MERCHANT_NOT_FOUND','missing merchant profiles are rejected'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a9000000-0000-0000-0000-000000000003','approved','Bypass review')$$,
  'P0001','REINSTATEMENT_REQUEST_REQUIRED',
  'generic admin RPC cannot reinstate a suspended merchant'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a9000000-0000-0000-0000-000000000003'),
  2,'rejected and repeated operations do not append audit events'
);
reset role;

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','a9000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(
  (select count(*)::integer from public.merchant_status_audit),
  0,'ordinary authenticated user cannot read admin audit rows'
);
reset role;
select set_config('request.jwt.claim.sub','a9000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a9000000-0000-0000-0000-000000000003'),
  2,'admin can read merchant status audit history'
);
reset role;

select * from finish();
rollback;
