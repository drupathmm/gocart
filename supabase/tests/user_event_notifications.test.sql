-- Contract checks for 20261027130000_user_event_notifications.sql.
-- Run only after the full reviewed GoCart migration chain on an isolated copy.
begin;
select plan(10);

select ok(
  to_regclass('public.user_notifications') is not null,
  'recipient-scoped user notification table exists'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'public.user_notifications'::regclass
      and c.contype = 'u'
      and pg_catalog.pg_get_constraintdef(c.oid) =
        'UNIQUE (recipient_id, event_type, entity_type, entity_id)'
  ),
  'event key deduplicates notification retries'
);

select ok(
  (select c.relrowsecurity from pg_catalog.pg_class c
   where c.oid = 'public.user_notifications'::regclass),
  'row-level security is enabled'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_policy p
    where p.polrelid = 'public.user_notifications'::regclass
      and p.polname = 'user_notifications_read_own'
      and p.polcmd = 'r'
      and pg_catalog.pg_get_expr(p.polqual,p.polrelid) like '%recipient_id%auth.uid%'
  ),
  'authenticated readers are restricted to their own notifications'
);

select ok(
  has_table_privilege('authenticated','public.user_notifications','SELECT')
  and not has_table_privilege('authenticated','public.user_notifications','INSERT')
  and not has_table_privilege('authenticated','public.user_notifications','UPDATE')
  and not has_table_privilege('anon','public.user_notifications','SELECT'),
  'clients cannot insert or change notification records directly'
);

select ok(
  has_function_privilege('authenticated',
    'public.mark_my_user_notification_read(bigint)','EXECUTE')
  and not has_function_privilege('anon',
    'public.mark_my_user_notification_read(bigint)','EXECUTE')
  and not has_function_privilege('service_role',
    'public.mark_my_user_notification_read(bigint)','EXECUTE'),
  'read-state RPC is authenticated-only'
);

select ok(
  (select count(*) = 5 from pg_catalog.pg_trigger t
   where not t.tgisinternal and t.tgenabled = 'O'
     and t.tgname in (
       'user_notifications_from_merchant_status_audit',
       'user_notifications_from_reinstatement_request',
       'user_notifications_from_order_items',
       'user_notifications_from_order_updates',
       'user_notifications_from_verified_payment'
     )),
  'status, reinstatement, order, and payment event triggers are enabled'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgname = 'user_notifications_from_verified_payment'
      and t.tgrelid = 'public.orders'::regclass
      and t.tgenabled = 'O'
      and not t.tgisinternal
  )
  and pg_catalog.pg_get_functiondef(
    'public.notify_verified_payment_event()'::regprocedure
  ) like '%public.has_verified_razorpay_capture(new.id)%'
  and pg_catalog.pg_get_functiondef(
    'public.notify_verified_payment_event()'::regprocedure
  ) like '%payment_verified%',
  'payment notice runs after the order transition and requires verified capture evidence'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.notify_merchant_status_event()'::regprocedure
  ) like '%merchant_rejected%'
  and pg_catalog.pg_get_functiondef(
    'public.notify_merchant_status_event()'::regprocedure
  ) like '%new.old_status = ''pending'' and new.new_status = ''rejected''%',
  'pending merchant rejection creates the corresponding user event'
);

select ok(
  (select count(*) = 6 from pg_catalog.pg_proc p
   where p.oid in (
     'public.emit_user_notification(uuid,text,text,text)'::regprocedure,
     'public.notify_merchant_status_event()'::regprocedure,
     'public.notify_reinstatement_request_event()'::regprocedure,
     'public.notify_order_item_event()'::regprocedure,
     'public.notify_order_event()'::regprocedure,
     'public.notify_verified_payment_event()'::regprocedure
   ) and p.prosecdef and p.proconfig @> array['search_path=""'])
  and pg_catalog.pg_get_functiondef(
    'public.notify_verified_payment_event()'::regprocedure
  ) like '%public.has_verified_razorpay_capture(new.id)%',
  'event writers use fixed search paths and payment notices require captured evidence'
);

select * from finish();
rollback;
