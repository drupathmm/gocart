begin;

select plan(46);

select ok(
  (select proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.place_order(text,text)'::regprocedure),
  'place_order uses an empty search_path'
);

select ok(
  (select proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.place_demo_order()'::regprocedure),
  'legacy place_demo_order uses an empty search_path'
);

select ok(
  not has_schema_privilege('anon', 'public', 'CREATE')
  and not has_schema_privilege('authenticated', 'public', 'CREATE')
  and not has_schema_privilege('service_role', 'public', 'CREATE'),
  'API roles cannot create objects in public'
);

select ok(
  has_function_privilege('authenticated', 'public.checkout_place_order(text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.checkout_place_order(text,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.checkout_place_order_cached(text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.checkout_place_order_cached(text,text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.checkout_place_order_cached(text,text)', 'EXECUTE'),
  'only authenticated clients can call the checkout wrappers'
);

select ok(
  not has_function_privilege('authenticated', 'public.place_order(text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.place_order(text,text)', 'EXECUTE'),
  'clients cannot bypass the idempotent checkout wrapper'
);

select ok(
  not has_function_privilege('authenticated', 'public.place_demo_order()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.place_demo_order()', 'EXECUTE'),
  'legacy no-key checkout is disabled for API clients'
);

select ok(
  (select qual like '%user_id%' and qual like '%auth.uid%'
   from pg_policies
   where schemaname = 'public' and tablename = 'orders'
     and policyname = 'Users can view own orders'),
  'buyers can read orders through the owner-scoped policy'
);

select ok(
  (select qual like '%merchant_id%' and qual like '%auth.uid%'
      and qual like '%user_id%'
   from pg_policies
   where schemaname = 'public' and tablename = 'order_items'
     and policyname = 'Buyers and approved merchants can view authorized order items'),
  'order-item reads are restricted to the buyer or matching merchant'
);

select ok(
  (select qual like '%merchant_status%' and qual like '%approved%'
      and qual like '%role%' and qual like '%merchant%'
   from pg_policies
   where schemaname = 'public' and tablename = 'order_items'
     and policyname = 'Buyers and approved merchants can view authorized order items'),
  'merchant order-item reads require current approved merchant authorization'
);

select ok(
  not has_table_privilege('authenticated', 'public.orders', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_items', 'INSERT')
  and (select relrowsecurity from pg_class where oid = 'public.idempotency_keys'::regclass)
  and not has_table_privilege('anon', 'public.idempotency_keys', 'SELECT')
  and not has_table_privilege('authenticated', 'public.idempotency_keys', 'SELECT')
  and not has_table_privilege('service_role', 'public.idempotency_keys', 'SELECT'),
  'order writes and idempotency response data remain inaccessible to API roles'
);

select ok(
  not has_column_privilege('anon', 'public.profiles', 'role', 'UPDATE')
  and not has_column_privilege('anon', 'public.profiles', 'merchant_status', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profiles', 'merchant_status', 'UPDATE')
  and not has_column_privilege('service_role', 'public.profiles', 'merchant_status', 'UPDATE')
  and not has_table_privilege('service_role', 'public.profiles', 'UPDATE'),
  'API clients cannot grant themselves privileged profile state'
);

select ok(
  to_regprocedure('public.approve_my_merchant_account()') is null,
  'the obsolete merchant self-approval RPC is not exposed'
);

select ok(
  to_regclass('public.profiles') is not null
  and to_regprocedure('public.set_initial_profile_status()') is not null
  and coalesce((
    select prosrc like '%new.merchant_status := ''pending''%'
        and prosrc not like '%app.merchant_auto_approval%'
    from pg_proc
    where oid = to_regprocedure('public.set_initial_profile_status()')::oid
  ), false)
  and exists (
    select 1 from pg_trigger
    where tgrelid = to_regclass('public.profiles')::oid
      and tgname = 'profiles_set_initial_status'
      and tgfoid = to_regprocedure('public.set_initial_profile_status()')::oid
      and tgenabled = 'O'
      and not tgisinternal
  ),
  'merchant signup always assigns pending status without a session override'
);

select ok(
  to_regprocedure('public.protect_profile_privileged_fields()') is not null
  and coalesce((
    select prosecdef
        and proconfig @> array['search_path=""']
        and prosrc like '%auth.uid()%'
        and prosrc like '%auth.role()%'
        and prosrc like '%p.role = ''admin''%'
        and prosrc not like '%app.merchant_auto_approval%'
    from pg_proc
    where oid = to_regprocedure('public.protect_profile_privileged_fields()')::oid
  ), false)
  and exists (
    select 1 from pg_trigger
    where tgrelid = to_regclass('public.profiles')::oid
      and tgfoid = to_regprocedure('public.protect_profile_privileged_fields()')::oid
      and (tgtype & 2) = 2
      and (tgtype & 16) = 16
      and tgenabled = 'O'
      and not tgisinternal
  )
  and not has_function_privilege(
    'anon', 'public.protect_profile_privileged_fields()', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated', 'public.protect_profile_privileged_fields()', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.protect_profile_privileged_fields()', 'EXECUTE'
  ),
  'profile status guard ignores the self-approval setting and is trigger-only'
);

select ok(
  (select prosecdef and proconfig @> array['search_path=""']
      and prosrc like '%auth.uid()%'
      and prosrc like '%p.role = ''admin''%'
      and prosrc like '%NOT_AUTHORIZED%'
   from pg_proc
   where oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure)
  and has_function_privilege(
    'authenticated', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'
  )
  and has_function_privilege(
    'authenticated', 'public.is_current_user_admin()', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'public.is_current_user_admin()', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.is_current_user_admin()', 'EXECUTE'
  ),
  'merchant status RPCs retain their authenticated-only admin checks'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'products'
      and policyname = 'Suspension catalog restriction for anon'
      and permissive = 'RESTRICTIVE'
      and roles = array['anon']::name[]
      and qual like '%gocart_private.is_approved_product_merchant%'
  )
  and exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'products'
      and policyname = 'Suspension catalog restriction for authenticated'
      and permissive = 'RESTRICTIVE'
      and roles = array['authenticated']::name[]
      and qual like '%gocart_private.is_approved_product_merchant%'
  ),
  'restrictive product policies bound catalog reads to approved merchants'
);

select ok(
  not has_table_privilege('anon', 'public.products', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.products', 'TRUNCATE')
  and case when to_regclass('public.promotions') is null then true
      else not has_table_privilege('anon', 'public.promotions', 'TRUNCATE')
        and not has_table_privilege('authenticated', 'public.promotions', 'TRUNCATE')
    end,
  'API clients cannot truncate products or promotions when present'
);

select ok(
  case when to_regclass('public.offers') is null then true
      else not has_table_privilege('anon', 'public.offers', 'TRUNCATE')
        and not has_table_privilege('authenticated', 'public.offers', 'TRUNCATE')
    end,
  'API clients cannot truncate offers when present'
);

select ok(
  (select with_check like '%merchant_status%' and with_check like '%approved%'
   from pg_policies
   where schemaname = 'public' and tablename = 'products'
     and policyname = 'Approved merchants insert own products'),
  'product inserts require approved merchant authorization'
);

select ok(
  (select qual like '%merchant_status%' and qual like '%approved%'
      and with_check like '%merchant_status%' and with_check like '%approved%'
   from pg_policies
   where schemaname = 'public' and tablename = 'products'
     and policyname = 'Approved merchants update own product fields'),
  'product updates require approved ownership before and after the change'
);

select ok(
  not has_table_privilege('authenticated', 'public.order_status_history', 'INSERT')
  and not has_table_privilege('authenticated', 'public.order_status_history', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.order_status_history', 'DELETE'),
  'ordinary clients cannot create or mutate order history'
);

-- Exercise product RLS using isolated auth/profile fixtures. This SQL test
-- runs inside a transaction and rolls every fixture back at the end.
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'security-approved@example.invalid'),
  ('10000000-0000-0000-0000-000000000002', 'security-pending@example.invalid'),
  ('10000000-0000-0000-0000-000000000003', 'security-suspended@example.invalid'),
  ('10000000-0000-0000-0000-000000000005', 'security-admin@example.invalid');

insert into public.profiles (id, name, email, role) values
  ('10000000-0000-0000-0000-000000000001', 'Approved Merchant', 'ignored@example.invalid', 'merchant'),
  ('10000000-0000-0000-0000-000000000002', 'Pending Merchant', 'ignored@example.invalid', 'merchant'),
  ('10000000-0000-0000-0000-000000000003', 'Suspended Merchant', 'ignored@example.invalid', 'merchant'),
  ('10000000-0000-0000-0000-000000000005', 'Admin', 'ignored@example.invalid', 'admin');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('app.merchant_auto_approval', 'true', true);
select throws_ok(
  $$update public.profiles set merchant_status = 'approved'
    where id = '10000000-0000-0000-0000-000000000001'$$,
  '42501',
  'PROFILE_PRIVILEGED_FIELD_CHANGE_DENIED',
  'a merchant cannot self-approve by setting the legacy session flag'
);
select set_config('app.merchant_auto_approval', '', true);

select is(
  (select merchant_status from public.profiles
   where id = '10000000-0000-0000-0000-000000000002'),
  'pending',
  'merchant signup creates a pending profile'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.admin_set_merchant_status(
  '10000000-0000-0000-0000-000000000001', 'approved', null
);
select public.admin_set_merchant_status(
  '10000000-0000-0000-0000-000000000003', 'suspended', null
);
reset role;

insert into public.products (
  merchant_id, name, original_price, offer_price, price, category
) values
  ('10000000-0000-0000-0000-000000000001', 'security-approved-product', 12, 10, 10, 'Electronics'),
  ('10000000-0000-0000-0000-000000000002', 'security-pending-product', 12, 10, 10, 'Electronics'),
  ('10000000-0000-0000-0000-000000000003', 'security-suspended-product', 12, 10, 10, 'Electronics');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$update public.profiles set merchant_status = 'suspended'
    where id = '10000000-0000-0000-0000-000000000001'$$,
  '42501',
  'permission denied for table profiles',
  'an authenticated merchant cannot change their own status directly'
);
select lives_ok(
  $$update public.profiles set name = 'Approved Merchant Updated'
    where id = '10000000-0000-0000-0000-000000000001'$$,
  'an authenticated user can still update their own profile name'
);
select lives_ok(
  $$insert into public.products (merchant_id, name, original_price, offer_price, price, category)
    values ('10000000-0000-0000-0000-000000000001', 'security-approved-insert', 12, 10, 10, 'Electronics')$$,
  'an approved merchant can create a product for their account'
);
select lives_ok(
  $$update public.products set name = 'hijacked-product' where name = 'security-pending-product'$$,
  'an approved merchant update request against another merchant is safely ignored'
);
select is(
  (select name from public.products where name = 'security-pending-product'),
  'security-pending-product',
  'an approved merchant cannot modify another merchant product'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$insert into public.products (merchant_id, name, original_price, offer_price, price, category)
    values ('10000000-0000-0000-0000-000000000002', 'security-pending-insert', 12, 10, 10, 'Electronics')$$,
  '42501',
  'new row violates row-level security policy for table "products"',
  'a pending merchant cannot create a product'
);
select lives_ok(
  $$update public.products set name = 'pending-edited-product' where name = 'security-pending-product'$$,
  'a pending merchant update request is safely ignored'
);
select is(
  (select name from public.products where name = 'security-pending-product'),
  'security-pending-product',
  'a pending merchant cannot modify an existing product'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$insert into public.products (merchant_id, name, original_price, offer_price, price, category)
    values ('10000000-0000-0000-0000-000000000003', 'security-suspended-insert', 12, 10, 10, 'Electronics')$$,
  '42501',
  'new row violates row-level security policy for table "products"',
  'a suspended merchant cannot create a product'
);
select lives_ok(
  $$update public.products set name = 'suspended-edited-product' where name = 'security-suspended-product'$$,
  'a suspended merchant update request is safely ignored'
);
select is(
  (select name from public.products where name = 'security-suspended-product'),
  'security-suspended-product',
  'a suspended merchant cannot modify an existing product'
);

reset role;

select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email)
values ('10000000-0000-0000-0000-000000000004', 'security-buyer@example.invalid');
insert into public.profiles (id, name, email, role)
values ('10000000-0000-0000-0000-000000000004', 'Checkout Buyer', 'ignored@example.invalid', 'user');
insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values (
  '10000000-0000-0000-0000-000000000001', 'security-checkout-product', 12, 10, 10, 10, 'Electronics'
);
insert into public.cart_items (user_id, product_id, quantity)
select '10000000-0000-0000-0000-000000000004', id, 2
from public.products where name = 'security-checkout-product';

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select is(
  (public.checkout_place_order_cached(null, 'security-idempotency-key-0001') ->> 'order_id')::uuid,
  public.checkout_place_order(null, 'security-idempotency-key-0001'),
  'repeating an idempotency key returns the same order through both checkout RPCs'
);
select is(
  (select response_payload ->> 'order_id'
   from public.idempotency_keys
   where idempotency_key = 'security-idempotency-key-0001'),
  (select resource_id::text
   from public.idempotency_keys
   where idempotency_key = 'security-idempotency-key-0001'),
  'checkout stores the original response payload behind the private idempotency ledger'
);
select is(
  (select count(*)::int from public.orders where idempotency_key = 'security-idempotency-key-0001'),
  1,
  'repeated checkout does not create a second order'
);
select is(
  (select total_amount from public.orders where idempotency_key = 'security-idempotency-key-0001'),
  20::numeric,
  'checkout total is calculated from the database product price and cart quantity'
);
select is(
  (select oi.unit_price from public.order_items oi join public.orders o on o.id = oi.order_id
   where o.idempotency_key = 'security-idempotency-key-0001'),
  10::numeric,
  'order item price is snapshotted from the database product'
);
select is(
  (select oi.quantity from public.order_items oi join public.orders o on o.id = oi.order_id
   where o.idempotency_key = 'security-idempotency-key-0001'),
  2,
  'order item quantity comes from the database cart'
);
select is(
  (select stock from public.products where name = 'security-checkout-product'),
  8,
  'stock is decremented once for an idempotent checkout'
);
select is(
  (select count(*)::int from public.cart_items
   where user_id = '10000000-0000-0000-0000-000000000004'),
  0,
  'successful checkout removes only its buyer cart rows'
);
reset role;

select set_config(
  'test.order_id',
  (select id::text from public.orders where idempotency_key = 'security-idempotency-key-0001'),
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select is(
  (select count(*)::int from public.order_items
   where order_id = current_setting('test.order_id')::uuid),
  1,
  'the buyer can read their own order item'
);
reset role;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::int from public.order_items
   where order_id = current_setting('test.order_id')::uuid),
  1,
  'an approved merchant can read their product order item'
);
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.admin_set_merchant_status(
  '10000000-0000-0000-0000-000000000001', 'suspended', null
);
reset role;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::int from public.order_items
   where order_id = current_setting('test.order_id')::uuid),
  0,
  'a suspended merchant cannot read historical product order items'
);
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
update public.profiles set role = 'user'
where id = '10000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::int from public.order_items
   where order_id = current_setting('test.order_id')::uuid),
  0,
  'a demoted account cannot read historical product order items'
);
reset role;

select * from finish();

rollback;
