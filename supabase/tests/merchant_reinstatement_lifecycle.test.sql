begin;

select plan(49);

select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure
     and p.proargnames = array['p_merchant_id','p_status','p_reason']::text[]
     and p.pronargdefaults = 0),
  'status RPC requires all named audited arguments, including a reason'
);
select ok(
  (select count(*) = 0 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_set_merchant_status'
     and p.pronargdefaults > 0),
  'status RPC has no defaulted argument that could omit the audit reason'
);
select ok(
  has_function_privilege('authenticated','public.merchant_request_reinstatement(text)','EXECUTE')
  and not has_function_privilege('anon','public.merchant_request_reinstatement(text)','EXECUTE')
  and not has_function_privilege('service_role','public.merchant_request_reinstatement(text)','EXECUTE'),
  'only authenticated sessions can call the merchant request endpoint'
);
select ok(
  has_function_privilege('authenticated','public.merchant_get_reinstatement_request()','EXECUTE')
  and not has_function_privilege('anon','public.merchant_get_reinstatement_request()','EXECUTE')
  and not has_function_privilege('service_role','public.merchant_get_reinstatement_request()','EXECUTE'),
  'merchant request lookup has authenticated-only execution'
);
select ok(
  has_function_privilege('authenticated','public.admin_list_merchant_reinstatement_requests()','EXECUTE')
  and not has_function_privilege('anon','public.admin_list_merchant_reinstatement_requests()','EXECUTE')
  and not has_function_privilege('service_role','public.admin_list_merchant_reinstatement_requests()','EXECUTE'),
  'admin queue execution is authenticated-only and still checks admin identity in function'
);
select ok(
  has_function_privilege('authenticated','public.admin_resolve_merchant_reinstatement(bigint,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.admin_resolve_merchant_reinstatement(bigint,text,text)','EXECUTE')
  and not has_function_privilege('service_role','public.admin_resolve_merchant_reinstatement(bigint,text,text)','EXECUTE'),
  'admin resolution execution is authenticated-only and still checks admin identity in function'
);
select ok(
  has_function_privilege('authenticated','public.admin_merchant_lifecycle_counts()','EXECUTE')
  and not has_function_privilege('anon','public.admin_merchant_lifecycle_counts()','EXECUTE')
  and not has_function_privilege('service_role','public.admin_merchant_lifecycle_counts()','EXECUTE'),
  'lifecycle counter execution is authenticated-only'
);
select ok(
  (select c.relrowsecurity from pg_catalog.pg_class c
   where c.oid = 'public.merchant_reinstatement_requests'::regclass)
  and not has_table_privilege('anon','public.merchant_reinstatement_requests','SELECT')
  and not has_table_privilege('authenticated','public.merchant_reinstatement_requests','SELECT')
  and not has_table_privilege('authenticated','public.merchant_reinstatement_requests','INSERT'),
  'request rows are protected by RLS and have no direct client table access'
);
select ok(
  (select count(*) = 1 from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'admin_resolve_merchant_reinstatement'),
  'the resolution endpoint has no unexpected overload'
);

select set_config('request.jwt.claim.sub','',true);
insert into auth.users (id,email) values
  ('a8000000-0000-0000-0000-000000000001','lifecycle-admin@example.invalid'),
  ('a8000000-0000-0000-0000-000000000002','lifecycle-merchant@example.invalid'),
  ('a8000000-0000-0000-0000-000000000003','lifecycle-buyer@example.invalid'),
  ('a8000000-0000-0000-0000-000000000004','lifecycle-pending@example.invalid');
insert into public.profiles (id,name,email,role) values
  ('a8000000-0000-0000-0000-000000000001','Lifecycle Admin','ignored','admin'),
  ('a8000000-0000-0000-0000-000000000002','Lifecycle Merchant','ignored','merchant'),
  ('a8000000-0000-0000-0000-000000000003','Lifecycle Buyer','ignored','user'),
  ('a8000000-0000-0000-0000-000000000004','Pending Merchant','ignored','merchant');

select is(
  (select merchant_status from public.profiles where id='a8000000-0000-0000-0000-000000000002'),
  'pending','new merchant profiles start pending'
);
select is(
  (select count(*)::integer from public.admin_merchant_notifications
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and event_type='pending_registration'),
  1,'registration creates one pending notification'
);
select is(
  (select count(*)::integer from public.admin_merchant_notifications
   where merchant_id='a8000000-0000-0000-0000-000000000004'
     and event_type='pending_registration'),
  1,'a separate registration gets its own single notification'
);

select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select throws_ok(
  $$select * from public.merchant_request_reinstatement('please review')$$,
  'P0001','NOT_AUTHORIZED','missing authenticated user identity is rejected'
);
select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000003',true);
select throws_ok(
  $$select * from public.merchant_request_reinstatement('please review')$$,
  'P0001','NOT_MERCHANT','ordinary buyer cannot submit a merchant request'
);
select throws_ok(
  $$select * from public.admin_list_merchant_reinstatement_requests()$$,
  'P0001','NOT_AUTHORIZED','ordinary buyer cannot read the admin review queue'
);
select throws_ok(
  $$select public.admin_resolve_merchant_reinstatement(999,'approved','No request')$$,
  'P0001','NOT_AUTHORIZED','ordinary buyer cannot resolve reinstatement requests'
);
reset role;

select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.admin_set_merchant_status(
  'a8000000-0000-0000-0000-000000000002','approved','Initial approval'
);
select public.admin_set_merchant_status(
  'a8000000-0000-0000-0000-000000000002','suspended','Policy review'
);
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a8000000-0000-0000-0000-000000000002','approved','Direct restore')$$,
  'P0001','REINSTATEMENT_REQUEST_REQUIRED',
  'generic status RPC cannot reinstate without a reviewed request'
);
select lives_ok(
  $$select public.admin_set_merchant_status(
      'a8000000-0000-0000-0000-000000000004','rejected','Application incomplete')$$,
  'admin can reject a pending merchant with an audited reason'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id='a8000000-0000-0000-0000-000000000004'),
  'rejected','rejection is a distinct terminal merchant status'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a8000000-0000-0000-0000-000000000004'
     and actor_id='a8000000-0000-0000-0000-000000000001'
     and old_status='pending' and new_status='rejected'
     and reason='Application incomplete'),
  1,'rejection is transactionally recorded in the audit history'
);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      'a8000000-0000-0000-0000-000000000004','approved','Try again')$$,
  'P0001','INVALID_MERCHANT_STATUS_TRANSITION',
  'a rejected merchant cannot bypass the reinstatement workflow'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id='a8000000-0000-0000-0000-000000000004'),
  'rejected','an invalid reactivation leaves rejected status unchanged'
);

select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select is(
  (select request_status from public.merchant_request_reinstatement(
    'The compliance issue has been resolved and documents are updated.')),
  'open','suspended merchant can submit an open account review request'
);
select is(
  (select count(*)::integer from public.merchant_reinstatement_requests
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and request_status='open'),
  1,'an open request is stored exactly once'
);
select is(
  (select request_id from public.merchant_request_reinstatement('retry after timeout')),
  (select id from public.merchant_reinstatement_requests
   where merchant_id='a8000000-0000-0000-0000-000000000002' and request_status='open'),
  'retry returns the existing open request instead of creating a duplicate'
);
select is(
  (select merchant_status from public.profiles where id='a8000000-0000-0000-0000-000000000002'),
  'suspended','submitting a request does not change merchant status'
);
select is(
  (select request_status from public.merchant_get_reinstatement_request()),
  'open','merchant can inspect their own request state'
);
reset role;

select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select is(
  (select pending_merchants from public.admin_merchant_lifecycle_counts()),
  0::bigint,'pending count reflects pending merchant profiles, not unread notices'
);
select is(
  (select rejected_merchants from public.admin_merchant_lifecycle_counts()),
  1::bigint,'rejected applications have a distinct lifecycle count'
);
select is(
  (select open_reinstatement_requests from public.admin_merchant_lifecycle_counts()),
  1::bigint,'open reinstatement count reflects request state'
);
select throws_ok(
  $$select public.admin_resolve_merchant_reinstatement(
      (select id from public.merchant_reinstatement_requests where request_status='open'),
      'pending','Invalid decision')$$,
  'P0001','INVALID_REINSTATEMENT_DECISION','admin cannot choose an unsupported decision'
);
select throws_ok(
  $$select public.admin_resolve_merchant_reinstatement(
      (select id from public.merchant_reinstatement_requests where request_status='open'),
      'approved','   ')$$,
  'P0001','INVALID_REASON','admin cannot approve reinstatement without a reason'
);
select is(
  (select count(*)::integer from public.admin_list_merchant_reinstatement_requests()),
  1,'admin queue lists the eligible suspended merchant request'
);
select is(
  public.admin_resolve_merchant_reinstatement(
    (select id from public.merchant_reinstatement_requests where request_status='open'),
    'rejected','Please provide updated compliance documents.'
  ),
  'rejected','admin can reject with a reason'
);
select is(
  (select merchant_status from public.profiles where id='a8000000-0000-0000-0000-000000000002'),
  'suspended','rejection leaves the merchant suspended'
);
select is(
  (select resolution_reason from public.merchant_reinstatement_requests
   where merchant_id='a8000000-0000-0000-0000-000000000002'
   order by id desc limit 1),
  'Please provide updated compliance documents.','rejection reason is retained'
);
select is(
  public.admin_resolve_merchant_reinstatement(
    (select id from public.merchant_reinstatement_requests
     where merchant_id='a8000000-0000-0000-0000-000000000002' order by id desc limit 1),
    'rejected','Please provide updated compliance documents.'
  ),
  'rejected','repeating the same resolution is idempotent'
);
reset role;

select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select public.merchant_request_reinstatement(
  'Updated compliance documents are now available for review.'
);
reset role;

create function public.gocart_test_reject_reinstatement_audit()
returns trigger language plpgsql set search_path = '' as $test$
begin
  raise exception 'TEST_REINSTATEMENT_AUDIT_BLOCKED';
end;
$test$;
create trigger gocart_test_reject_reinstatement_audit
before insert on public.merchant_status_audit
for each row execute function public.gocart_test_reject_reinstatement_audit();

select set_config('request.jwt.claim.sub','a8000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select throws_ok(
  $$select public.admin_resolve_merchant_reinstatement(
      (select id from public.merchant_reinstatement_requests
       where merchant_id='a8000000-0000-0000-0000-000000000002'
         and request_status='open'), 'approved','Verified documents')$$,
  'P0001','TEST_REINSTATEMENT_AUDIT_BLOCKED',
  'audit failure aborts reinstatement and request resolution'
);
reset role;
select is(
  (select merchant_status from public.profiles where id='a8000000-0000-0000-0000-000000000002'),
  'suspended','audit failure leaves the merchant suspended'
);
select is(
  (select count(*)::integer from public.merchant_reinstatement_requests
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and request_status='open'),
  1,'audit failure leaves the request open for retry'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a8000000-0000-0000-0000-000000000002'),
  2,'audit failure leaves prior status history unchanged'
);
select is(
  (select resolved_status from public.admin_merchant_notifications
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and event_type='pending_registration'),
  'suspended','audit failure rolls back the registration notification side effect'
);
drop trigger gocart_test_reject_reinstatement_audit on public.merchant_status_audit;
drop function public.gocart_test_reject_reinstatement_audit();

select is(
  public.admin_resolve_merchant_reinstatement(
    (select id from public.merchant_reinstatement_requests
     where merchant_id='a8000000-0000-0000-0000-000000000002'
       and request_status='open'), 'approved','Verified documents'
  ),
  'approved','authorized admin can approve reinstatement'
);
select is(
  public.admin_resolve_merchant_reinstatement(
    (select id from public.merchant_reinstatement_requests
     where merchant_id='a8000000-0000-0000-0000-000000000002'
     order by id desc limit 1), 'approved','Retry with changed note'
  ),
  'approved','repeating an approved resolution is idempotent'
);
reset role;
select is(
  (select merchant_status from public.profiles where id='a8000000-0000-0000-0000-000000000002'),
  'approved','merchant is restored only after admin resolution'
);
select is(
  (select request_status from public.merchant_reinstatement_requests
   where merchant_id='a8000000-0000-0000-0000-000000000002'
   order by id desc limit 1),
  'approved','approved request is resolved durably'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and old_status='suspended' and new_status='approved'
     and reason='Verified documents'),
  1,'reinstatement audit records prior/new status and admin note'
);
select is(
  (select count(*)::integer from public.admin_merchant_notifications
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and event_type='pending_registration'),
  1,'approval and reinstatement do not duplicate registration notifications'
);
select is(
  (select count(*)::integer from public.merchant_status_audit
   where merchant_id='a8000000-0000-0000-0000-000000000002'
     and old_status='suspended' and new_status='approved'),
  1,'replayed reinstatement does not create a second audit event'
);

select * from finish();
rollback;
