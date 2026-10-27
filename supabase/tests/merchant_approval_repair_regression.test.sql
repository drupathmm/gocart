begin;

select plan(58);

select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_set_merchant_status'
     and p.pronargs = 3
     and p.proargnames = array['p_merchant_id','p_status','p_reason']::text[]
     and p.pronargdefaults = 0
     and p.prorettype = 'void'::regtype::oid),
  'status RPC has exactly the expected named three-argument contract'
);
select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_set_merchant_status'),
  'the obsolete or unexpected status RPC overload is absent'
);
select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_list_merchant_notifications'
     and p.pronargs = 0 and p.proretset
     and p.proargnames = array[
       'notification_id','merchant_id','merchant_name','merchant_email',
       'merchant_created_at','merchant_status','notification_created_at',
       'resolved_at','resolved_status','read_at'
     ]::text[])
  and (select count(*) = 1 from pg_catalog.pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'admin_list_merchant_notifications'),
  'admin notification list has its expected contract and no overloads'
);
select ok(
  has_function_privilege('authenticated',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
  and not has_function_privilege('anon',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE')
  and not has_function_privilege('service_role',
    'public.admin_set_merchant_status(uuid,text,text)','EXECUTE'),
  'status RPC execution is limited to authenticated clients'
);
select ok(
  has_function_privilege('authenticated',
    'public.admin_list_merchant_notifications()','EXECUTE')
  and not has_function_privilege('anon',
    'public.admin_list_merchant_notifications()','EXECUTE')
  and not has_function_privilege('service_role',
    'public.admin_list_merchant_notifications()','EXECUTE'),
  'notification list execution is limited to authenticated clients'
);

select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id,email) values
  ('a7000000-0000-0000-0000-000000000001','repair-admin@example.invalid'),
  ('a7000000-0000-0000-0000-000000000002','repair-buyer@example.invalid'),
  ('a7000000-0000-0000-0000-000000000003','repair-merchant@example.invalid'),
  ('a7000000-0000-0000-0000-000000000004','repair-admin-two@example.invalid'),
  ('a7000000-0000-0000-0000-000000000005','signup-merchant@example.invalid');
insert into public.profiles (id,name,email,role) values
  ('a7000000-0000-0000-0000-000000000001','Repair Admin','ignored@example.invalid','admin'),
  ('a7000000-0000-0000-0000-000000000002','Repair Buyer','ignored@example.invalid','user'),
  ('a7000000-0000-0000-0000-000000000003','Repair Merchant','ignored@example.invalid','merchant'),
  ('a7000000-0000-0000-0000-000000000004','Second Repair Admin','ignored@example.invalid','admin');

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',null)$$,
  'P0001','NOT_AUTHORIZED',
  'an authenticated database role without a user identity is rejected'
);
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000002',true);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',null)$$,
  'P0001','NOT_AUTHORIZED',
  'a non-admin profile cannot approve a merchant'
);
select throws_ok(
  $$select * from public.admin_list_merchant_notifications()$$,
  'P0001','NOT_AUTHORIZED','a non-admin profile cannot list admin notifications'
);
select throws_ok(
  $$select public.admin_mark_merchant_notification_read(
      (select id from public.admin_merchant_notifications limit 1))$$,
  'P0001','NOT_AUTHORIZED','a non-admin profile cannot change notification read state'
);
select set_config('app.merchant_auto_approval','true',true);
reset role;
grant update (merchant_status) on public.profiles to authenticated;
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select throws_ok(
  $$update public.profiles set merchant_status = 'approved'
    where id = 'a7000000-0000-0000-0000-000000000003'$$,
  '42501','PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED',
  'the legacy setting reaches the trigger but cannot authorize direct status change'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',null)$$,
  'P0001','NOT_AUTHORIZED',
  'a merchant cannot self-approve through the RPC even with the legacy setting'
);
reset role;
revoke update (merchant_status) on public.profiles from authenticated;

-- Exercise the signup trigger as the authenticated owner. It must replace a
-- caller-supplied email with auth.users.email and assign pending status.
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000005',true);
set local role authenticated;
select lives_ok(
  $$insert into public.profiles(id,name,email,role)
    values ('a7000000-0000-0000-0000-000000000005','New Merchant',
      'spoofed@example.invalid','merchant')$$,
  'the authenticated owner can create their own merchant profile'
);
reset role;
select is(
  (select email from public.profiles where id='a7000000-0000-0000-0000-000000000005'),
  'signup-merchant@example.invalid','signup uses the authoritative auth.users email'
);
select is(
  (select merchant_status from public.profiles where id='a7000000-0000-0000-0000-000000000005'),
  'pending','authenticated merchant signup begins pending'
);
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000005',true);
set local role authenticated;
select throws_ok(
  $$insert into public.profiles(id,name,email,role)
    values ('a7000000-0000-0000-0000-000000000005','Attempt Admin',
      'signup-merchant@example.invalid','admin')$$,
  'P0001','ADMIN_PROFILE_CREATION_NOT_ALLOWED',
  'an authenticated user cannot create an admin profile'
);
reset role;
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(
  $$insert into public.profiles(id,name,email,role)
    values ('a7000000-0000-0000-0000-000000000003','Impersonated Merchant',
      'repair-merchant@example.invalid','user')$$,
  'P0001','PROFILE_OWNER_MISMATCH',
  'an authenticated user cannot create a profile for another auth identity'
);
reset role;

-- Registration notices are unique per merchant/event. Replaying the profile
-- status trigger path must not create another row.
update public.profiles set role='merchant'
where id='a7000000-0000-0000-0000-000000000005';
select is(
  (select count(*)::integer from public.admin_merchant_notifications
   where merchant_id='a7000000-0000-0000-0000-000000000005'
     and event_type='pending_registration'),
  1,'replayed registration notification trigger remains deduplicated'
);
select is(
  (select count(*)::integer from public.profiles
   where role='merchant' and merchant_status='pending'),
  2,'pending requests are counted from pending merchant profiles'
);

select is(
  public.admin_unread_merchant_notification_count(),
  2,'unread notification count starts independently for the first admin'
);
select lives_ok(
  $$select public.admin_mark_merchant_notification_read(
      (select id from public.admin_merchant_notifications
       where merchant_id='a7000000-0000-0000-0000-000000000003'))$$,
  'first admin can mark one registration notification read'
);
select is(
  public.admin_unread_merchant_notification_count(),
  1,'first admin unread count changes only for their read state'
);
reset role;
select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000004',true);
set local role authenticated;
select is(
  public.admin_unread_merchant_notification_count(),
  2,'second admin retains an independent unread count'
);
select lives_ok(
  $$select public.admin_mark_merchant_notification_read(
      (select id from public.admin_merchant_notifications
       where merchant_id='a7000000-0000-0000-0000-000000000003'))$$,
  'second admin can record their own read state'
);
select is(
  public.admin_unread_merchant_notification_count(),
  1,'second admin unread count changes only after their own read'
);
reset role;

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid='public.admin_merchant_notifications'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class
       where oid='public.admin_merchant_notification_reads'::regclass)
  and not has_table_privilege('authenticated','public.admin_merchant_notifications','SELECT')
  and not has_table_privilege('authenticated','public.admin_merchant_notification_reads','SELECT')
  and not has_table_privilege('anon','public.admin_merchant_notifications','SELECT')
  and not has_table_privilege('anon','public.admin_merchant_notification_reads','SELECT')
  and not has_function_privilege('anon','public.admin_unread_merchant_notification_count()','EXECUTE')
  and not has_function_privilege('anon','public.admin_mark_merchant_notification_read(bigint)','EXECUTE'),
  'notification data is protected by RLS, table grants, and RPC execution grants'
);

select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select throws_ok(
  $$select * from public.admin_merchant_notifications$$,
  '42501','ordinary authenticated users cannot read admin notifications directly'
);
select throws_ok(
  $$insert into public.admin_merchant_notifications(merchant_id,event_type)
    values ('a7000000-0000-0000-0000-000000000003','pending_registration')$$,
  '42501','ordinary authenticated users cannot create admin notifications'
);
select throws_ok(
  $$update public.admin_merchant_notifications set resolved_status='approved'$$,
  '42501','ordinary authenticated users cannot modify admin notifications'
);
select throws_ok(
  $$insert into public.admin_merchant_notification_reads(notification_id,admin_id)
    select id,'a7000000-0000-0000-0000-000000000002'
    from public.admin_merchant_notifications limit 1$$,
  '42501','ordinary authenticated users cannot mutate admin read state directly'
);
select throws_ok(
  $$update public.admin_merchant_notification_reads set read_at=now()$$,
  '42501','ordinary authenticated users cannot update admin read state directly'
);
reset role;
select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select throws_ok(
  $$select * from public.admin_merchant_notifications$$,
  '42501','anonymous callers cannot read admin notification rows'
);
select throws_ok(
  $$select * from public.admin_list_merchant_notifications()$$,
  '42501','anonymous callers cannot execute the admin notification RPC'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',null)$$,
  '42501','anonymous callers cannot execute the admin status RPC'
);
select throws_ok(
  $$insert into public.admin_merchant_notification_reads(notification_id,admin_id)
    select id,'a7000000-0000-0000-0000-000000000001'
    from public.admin_merchant_notifications limit 1$$,
  '42501','anonymous callers cannot mutate admin notification read state'
);
select throws_ok(
  $$update public.admin_merchant_notification_reads set read_at=now()$$,
  '42501','anonymous callers cannot update admin notification read state'
);
reset role;
select set_config('request.jwt.claim.role','authenticated',true);

select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','pending',null)$$,
  'P0001','INVALID_MERCHANT_STATUS',
  'the admin RPC rejects unsupported status values'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000099','approved',null)$$,
  'P0001','MERCHANT_NOT_FOUND',
  'the admin RPC rejects missing or non-merchant targets'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000002','approved',null)$$,
  'P0001','MERCHANT_NOT_FOUND',
  'the admin RPC rejects a profile that is not a merchant'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',repeat('x',501))$$,
  'P0001','INVALID_REASON',
  'the admin RPC rejects an overlong audit reason'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved',null)$$,
  'P0001','INVALID_REASON',
  'the admin RPC requires a reason argument and rejects NULL'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved','   ')$$,
  'P0001','INVALID_REASON',
  'the admin RPC rejects a blank reason'
);
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved','Reviewed')$$,
  'an authenticated admin can approve the intended merchant'
);
reset role;
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id = 'a7000000-0000-0000-0000-000000000003'
     and actor_id = 'a7000000-0000-0000-0000-000000000001'
     and old_status = 'pending' and new_status = 'approved' and reason = 'Reviewed'),
  1,
  'the profile transition and actor/reason audit row are recorded together'
);

select set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved','Repeated request')$$,
  'repeating the current status is an idempotent success'
);
reset role;
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id = 'a7000000-0000-0000-0000-000000000003'),
  1,
  'a repeated same-status request does not add a duplicate audit event'
);

create function public.gocart_test_reject_merchant_audit_insert()
returns trigger language plpgsql set search_path = '' as $test$
begin
  raise exception 'TEST_AUDIT_INSERT_BLOCKED';
end;
$test$;
create trigger gocart_test_reject_merchant_audit_insert
before insert on public.merchant_status_audit
for each row execute function public.gocart_test_reject_merchant_audit_insert();

set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','suspended','Rollback check')$$,
  'P0001','TEST_AUDIT_INSERT_BLOCKED',
  'an audit insertion failure aborts the status change transaction'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id = 'a7000000-0000-0000-0000-000000000003'),
  'approved',
  'audit failure leaves the merchant status unchanged'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id = 'a7000000-0000-0000-0000-000000000003'),
  1,
  'audit failure leaves the audit history unchanged'
);
select is(
  (select resolved_status from public.admin_merchant_notifications
   where merchant_id = 'a7000000-0000-0000-0000-000000000003'
     and event_type = 'pending_registration'),
  'approved',
  'audit failure rolls back the notification resolution side effect too'
);

drop trigger gocart_test_reject_merchant_audit_insert on public.merchant_status_audit;
drop function public.gocart_test_reject_merchant_audit_insert();
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','suspended','Policy review')$$,
  'authorized admin can suspend an approved merchant'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000003','approved','Direct restore')$$,
  'P0001','REINSTATEMENT_REQUEST_REQUIRED',
  'generic status RPC rejects suspended-to-approved without review'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id='a7000000-0000-0000-0000-000000000003'),
  'suspended','rejected direct reinstatement leaves status suspended'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a7000000-0000-0000-0000-000000000003'),
  2,'rejected direct reinstatement leaves audit history unchanged'
);

select lives_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000005','rejected','Application incomplete')$$,
  'authorized admin can reject a pending merchant with a reason'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id='a7000000-0000-0000-0000-000000000005'),
  'rejected','rejection moves the pending merchant to rejected'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a7000000-0000-0000-0000-000000000005'
     and actor_id='a7000000-0000-0000-0000-000000000001'
     and old_status='pending' and new_status='rejected'
     and reason='Application incomplete'),
  1,'rejection records the actor, transition, and reason'
);
select is(
  (select resolved_status from public.admin_merchant_notifications
   where merchant_id='a7000000-0000-0000-0000-000000000005'
     and event_type='pending_registration'),
  'rejected','rejection resolves the registration alert in the same transaction'
);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a7000000-0000-0000-0000-000000000005','approved','Try again')$$,
  'P0001','INVALID_MERCHANT_STATUS_TRANSITION',
  'a rejected registration cannot be silently reactivated through the status RPC'
);
reset role;

select * from finish();
rollback;
