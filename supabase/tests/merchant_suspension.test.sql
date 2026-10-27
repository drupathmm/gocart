begin;

select plan(40);

select has_table('public', 'merchant_status_audit',
  'merchant status transitions have an audit table');

select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.merchant_status_audit'::regclass),
  'merchant status audit has row-level security enabled'
);

select ok(
  has_table_privilege('authenticated', 'public.merchant_status_audit', 'SELECT'),
  'authenticated admins can query the audit table subject to its policy'
);

select ok(
  not has_table_privilege('anon', 'public.merchant_status_audit', 'SELECT')
  and not has_table_privilege('authenticated', 'public.merchant_status_audit', 'INSERT')
  and not has_table_privilege('authenticated', 'public.merchant_status_audit', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.merchant_status_audit', 'DELETE'),
  'clients cannot read anonymously or write audit records directly'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'merchant_status_audit'
      and policyname = 'Admins can view merchant status audit'
      and qual like '%is_current_user_admin%'
  ),
  'audit reads are restricted to the authenticated admin check'
);

select ok(
  not (select attnotnull from pg_catalog.pg_attribute
       where attrelid = 'public.merchant_status_audit'::regclass
         and attname = 'old_status' and attnum > 0 and not attisdropped),
  'the audit old_status column allows NULL for an unknown prior state'
);

select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc
   where oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure),
  'merchant status RPC is SECURITY DEFINER with an empty search_path'
);

select ok(
  has_function_privilege('authenticated',
    'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.admin_set_merchant_status(uuid,text,text)', 'EXECUTE'),
  'only authenticated callers can invoke the admin-checked status RPC'
);

select ok(
  (select prosrc like '%auth.uid()%' and prosrc like '%p.role = ''admin''%'
      and prosrc like '%for update%' and prosrc like '%merchant_status_audit%'
   from pg_proc
   where oid = 'public.admin_set_merchant_status(uuid,text,text)'::regprocedure),
  'status changes derive the actor, lock the merchant, and write an audit row'
);

select ok(
  exists (select 1 from pg_namespace where nspname = 'gocart_private'),
  'catalog visibility helper schema exists'
);

select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc
   where oid = 'gocart_private.is_approved_product_merchant(uuid)'::regprocedure),
  'catalog helper is SECURITY DEFINER with an empty search_path'
);

select ok(
  to_regprocedure('public.is_approved_product_merchant(uuid)') is null,
  'catalog authorization helper is not left in the exposed public schema'
);

select ok(
  has_function_privilege('anon',
    'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'gocart_private.is_approved_product_merchant(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.is_current_user_admin()', 'EXECUTE'),
  'catalog readers can evaluate visibility without exposing the admin helper'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'products'
      and policyname = 'Approved merchant catalog is readable'
      and roles = array['anon']::name[]
      and qual like '%gocart_private.is_approved_product_merchant%'
  ),
  'anonymous catalog visibility depends on approved merchant status'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'products'
      and policyname = 'Authenticated approved merchant catalog is readable'
      and roles = array['authenticated']::name[]
      and qual like '%gocart_private.is_approved_product_merchant%'
      and qual like '%is_current_user_admin%'
  ),
  'authenticated catalog visibility preserves merchant-owner and admin access'
);

select ok(
  (select count(*) = 3
   from pg_trigger
   where not tgisinternal
     and (tgname in (
       'cart_items_require_approved_merchant_insert',
       'cart_items_require_approved_merchant_update',
       'order_items_require_approved_merchant'
     ))),
  'cart changes and new order items have merchant-status guards'
);

select ok(
  (select count(*) = 2
   from pg_proc
   where oid in (
     'public.guard_active_merchant_cart_item()'::regprocedure,
     'public.guard_active_merchant_order_item()'::regprocedure
   )
     and prosecdef
     and proconfig @> array['search_path=""']
     and not has_function_privilege('anon', oid, 'EXECUTE')
     and not has_function_privilege('authenticated', oid, 'EXECUTE')),
  'merchant guards are hardened trigger-only SECURITY DEFINER functions'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.merchant_status_audit'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%length(reason) <= 500%'
  ),
  'audit reason length is bounded'
);

-- Isolated fixtures are rolled back with this test transaction.
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users (id, email) values
  ('90000000-0000-0000-0000-000000000001', 'suspension-approved@example.invalid'),
  ('90000000-0000-0000-0000-000000000002', 'suspension-suspended@example.invalid'),
  ('90000000-0000-0000-0000-000000000003', 'suspension-pending@example.invalid'),
  ('90000000-0000-0000-0000-000000000004', 'suspension-buyer@example.invalid'),
  ('90000000-0000-0000-0000-000000000005', 'suspension-admin@example.invalid');

insert into public.profiles (id, name, email, role) values
  ('90000000-0000-0000-0000-000000000001', 'Approved Merchant', 'ignored@example.invalid', 'merchant'),
  ('90000000-0000-0000-0000-000000000002', 'Suspended Merchant', 'ignored@example.invalid', 'merchant'),
  ('90000000-0000-0000-0000-000000000003', 'Pending Merchant', 'ignored@example.invalid', 'merchant'),
  ('90000000-0000-0000-0000-000000000004', 'Buyer', 'ignored@example.invalid', 'user'),
  ('90000000-0000-0000-0000-000000000005', 'Admin', 'ignored@example.invalid', 'admin');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select public.admin_set_merchant_status(
  '90000000-0000-0000-0000-000000000001', 'approved', null
);
select public.admin_set_merchant_status(
  '90000000-0000-0000-0000-000000000002', 'suspended', null
);
reset role;

insert into public.merchant_status_audit (
  merchant_id, actor_id, old_status, new_status, reason, changed_at
) values (
  '90000000-0000-0000-0000-000000000001',
  '90000000-0000-0000-0000-000000000005',
  'pending', 'approved', 'suspension-preservation-sentinel',
  '2026-01-01 00:00:00+00'
);

select lives_ok(
  $$insert into public.merchant_status_audit (
      merchant_id, actor_id, old_status, new_status, reason
    ) values (
      '90000000-0000-0000-0000-000000000001',
      '90000000-0000-0000-0000-000000000005',
      null, 'approved', 'suspension-null-old-status'
    )$$,
  'the audit constraint accepts a NULL old status'
);

insert into public.products (
  merchant_id, name, original_price, offer_price, price, stock, category
) values
  ('90000000-0000-0000-0000-000000000001', 'suspension-test-approved', 12, 10, 10, 5, 'Electronics'),
  ('90000000-0000-0000-0000-000000000002', 'suspension-test-suspended', 12, 10, 10, 5, 'Electronics'),
  ('90000000-0000-0000-0000-000000000003', 'suspension-test-pending', 12, 10, 10, 5, 'Electronics');

select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select is(
  (select count(*)::int from public.products
   where name like 'suspension-test-%'),
  1,
  'anonymous customers see only products from approved merchants'
);
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products
   where name like 'suspension-test-%'),
  3,
  'an authorized admin can inspect all merchant products'
);
reset role;

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$select public.admin_set_merchant_status(
      '90000000-0000-0000-0000-000000000003', 'approved', null)$$,
  'P0001', 'NOT_AUTHORIZED',
  'a buyer cannot approve a merchant'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id = '90000000-0000-0000-0000-000000000003'),
  'pending',
  'a rejected buyer approval request leaves the merchant pending'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      '90000000-0000-0000-0000-000000000003', 'approved', 'Reviewed')$$,
  'an authenticated admin can approve a pending merchant'
);
reset role;
select is(
  (select merchant_status from public.profiles
   where id = '90000000-0000-0000-0000-000000000003'),
  'approved',
  'approval updates the intended merchant status'
);
select is(
  (select actor_id from public.merchant_status_audit
   where merchant_id = '90000000-0000-0000-0000-000000000003'
   order by changed_at desc, id desc limit 1),
  '90000000-0000-0000-0000-000000000005'::uuid,
  'audit actor is derived from the authenticated identity'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      '90000000-0000-0000-0000-000000000001', 'suspended', 'Policy review')$$,
  'an authenticated admin can suspend an approved merchant'
);
reset role;
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select is(
  (select count(*)::int from public.products
   where name like 'suspension-test-%'),
  2,
  'suspension hides the merchant product without deleting it'
);
reset role;

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      '90000000-0000-0000-0000-000000000001', 'approved', null)$$,
  'an authenticated admin can restore a suspended merchant'
);
reset role;
select set_config('request.jwt.claim.role', 'anon', true);
set local role anon;
select is(
  (select count(*)::int from public.products
   where name like 'suspension-test-%'),
  3,
  'restoration restores catalog visibility for the existing product'
);
reset role;
select is(
  (select count(*)::int from public.products
   where name like 'suspension-test-%'),
  3,
  'approval and suspension preserve all product rows'
);
select is(
  (select count(*)::int from public.merchant_status_audit
   where merchant_id = '90000000-0000-0000-0000-000000000001'
     and actor_id = '90000000-0000-0000-0000-000000000005'
     and old_status = 'pending'
     and new_status = 'approved'
     and reason = 'suspension-preservation-sentinel'
     and changed_at = '2026-01-01 00:00:00+00'::timestamptz),
  1,
  'pre-existing audit history remains unchanged across later transitions'
);
select is(
  (select count(*)::int from public.merchant_status_audit
   where reason = 'suspension-null-old-status' and old_status is null),
  1,
  'a recorded audit row can preserve an unknown prior status'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$insert into public.cart_items (user_id, product_id, quantity)
    select '90000000-0000-0000-0000-000000000004', id, 1
    from public.products where name = 'suspension-test-suspended'$$,
  'P0001', 'MERCHANT_UNAVAILABLE',
  'a buyer cannot add a suspended merchant product to a cart'
);
select lives_ok(
  $$insert into public.cart_items (user_id, product_id, quantity)
    select '90000000-0000-0000-0000-000000000004', id, 2
    from public.products where name = 'suspension-test-approved'$$,
  'a buyer may add an approved merchant product before suspension'
);
reset role;

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select lives_ok(
  $$select public.admin_set_merchant_status(
      '90000000-0000-0000-0000-000000000001', 'suspended', null)$$,
  'admin suspension applies while a buyer has a stale cart line'
);
reset role;
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$select public.checkout_place_order(null, 'suspension-checkout-key-0001')$$,
  'P0001', 'MERCHANT_UNAVAILABLE',
  'checkout rejects a stale cart line after merchant suspension'
);
reset role;
select is(
  (select count(*)::int from public.orders
   where idempotency_key = 'suspension-checkout-key-0001'),
  0,
  'rejected checkout creates no order'
);
select is(
  (select stock from public.products
   where name = 'suspension-test-approved'),
  5,
  'rejected checkout does not decrement stock'
);
select is(
  (select count(*)::int from public.cart_items ci
   join public.products p on p.id = ci.product_id
   where ci.user_id = '90000000-0000-0000-0000-000000000004'
     and p.name = 'suspension-test-approved'),
  1,
  'rejected checkout retains the buyer cart line'
);

select * from finish();

rollback;
