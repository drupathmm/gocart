begin;

select plan(8);

select ok(
  to_regclass('public.order_status_history') is not null,
  'order status history table exists'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'order_status_history'
      and column_name = 'actor_id'
  ),
  'history records the verified actor ID when available'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname = 'order_status_history_record_insert'
      and not tgisinternal
  ),
  'order creation is recorded in status history'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.orders'::regclass
      and tgname = 'order_status_history_record_update'
      and not tgisinternal
  ),
  'order status changes are recorded in status history'
);

select ok(
  not has_table_privilege('authenticated', 'public.orders', 'UPDATE'),
  'authenticated clients cannot update orders directly'
);

select ok(
  not has_table_privilege('authenticated', 'public.order_status_history', 'INSERT'),
  'authenticated clients cannot insert fake history records'
);

select ok(
  not has_table_privilege('authenticated', 'public.order_status_history', 'DELETE'),
  'authenticated clients cannot delete history records'
);

select ok(
  not has_table_privilege('service_role', 'public.order_status_history', 'INSERT'),
  'server API clients cannot insert history outside the database trigger'
);

select * from finish();

rollback;
