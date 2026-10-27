-- Run only against an explicitly identified, owner-approved restored copy of
-- the legacy GoCart baseline, after the candidate patch is installed there.
-- Never run this test against live GoCart. pgTAP fixtures below roll back.
begin;

select plan(28);

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE')
  and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'approve_my_merchant_account'
      and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('service_role', p.oid, 'EXECUTE')
        or exists (
          select 1 from pg_catalog.aclexplode(
            coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
          ) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'
        ))
  ),
  'the legacy merchant self-approval RPC is absent or unavailable to clients'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_attribute a
    cross join (values ('anon'), ('authenticated'), ('service_role')) r(role_name)
    where a.attrelid = 'public.profiles'::regclass
      and a.attnum > 0 and not a.attisdropped and a.attname <> 'name'
      and has_column_privilege(r.role_name, 'public.profiles', a.attname, 'UPDATE')
  ),
  'application roles can update only the profile name directly'
);

select ok(
  (select relrowsecurity from pg_catalog.pg_class
   where oid = 'public.products'::regclass)
  and exists (
    select 1 from pg_catalog.pg_policy p
    where p.polrelid = 'public.products'::regclass
      and p.polname in (
        'Merchant approval required for product reads',
        'Suspension catalog restriction for anon',
        'Suspension catalog restriction for authenticated'
      )
      and not p.polpermissive and p.polcmd = 'r'
  ),
  'a restrictive product policy gates even older permissive catalog policies'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = coalesce(
      to_regprocedure('gocart_private.product_visible_to_requester(uuid)'),
      to_regprocedure('gocart_private.is_approved_product_merchant(uuid)')
    )
      and p.prosecdef and p.proconfig @> array['search_path=""']
      and has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
      and not exists (
        select 1 from pg_catalog.aclexplode(
          coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
        ) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'
      )
  ),
  'catalog helper is hardened and exposes only its boolean check'
);

select ok(
  (select count(*) = 3 from pg_catalog.pg_trigger t
   where not t.tgisinternal and t.tgenabled = 'O'
     and t.tgname in (
       'cart_items_require_approved_merchant_insert',
       'cart_items_require_approved_merchant_update',
       'order_items_require_approved_merchant'
     )),
  'cart insert/update and order-item insert guards are enabled'
);

select ok(
  (select count(*) = 2 from pg_catalog.pg_proc p
   where p.oid in (
     'public.guard_active_merchant_cart_item()'::regprocedure,
     'public.guard_active_merchant_order_item()'::regprocedure
   ) and p.prosecdef and p.proconfig @> array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
     and not exists (
       select 1 from pg_catalog.aclexplode(
         coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
       ) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'
     )),
  'write guards are trigger-only SECURITY DEFINER functions'
);

select ok(
  not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    join pg_catalog.pg_class c on c.oid = 'public.profiles'::regclass
    where p.oid in (
      coalesce(
        to_regprocedure('gocart_private.product_visible_to_requester(uuid)'),
        to_regprocedure('gocart_private.is_approved_product_merchant(uuid)')
      ),
      'public.guard_active_merchant_cart_item()'::regprocedure,
      'public.guard_active_merchant_order_item()'::regprocedure
    )
      and not (r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
  ),
  'security definer functions can read merchant status without profile RLS recursion'
);

select ok(
  (select count(*) = 2
   from pg_catalog.pg_proc p
   where p.oid in (
      'public.guard_active_merchant_cart_item()'::regprocedure,
      'public.guard_active_merchant_order_item()'::regprocedure
    ) and p.prosrc ilike '%for share%'),
  'write guards lock merchant status rows against concurrent status updates'
);
select ok(
  (select p.prosrc like '%order by pr.id for share of pr%'
          and position('merchant_status is distinct from ''approved''' in p.prosrc)
            < position('insert into public.orders' in p.prosrc)
   from pg_catalog.pg_proc p
   where p.oid = 'public.place_demo_order()'::regprocedure),
  'legacy checkout locks all merchant profiles in deterministic order and validates status before order effects'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'admin_set_merchant_status'
      and p.pronargs in (2, 3)
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ),
  'an authenticated admin status workflow remains without anonymous execution'
);

-- Behavioral fixtures target the verified legacy schema: buyer_id orders,
-- offer_price products, the two-argument admin RPC, and place_demo_order().
-- The enclosing transaction rolls back every fixture and attempted checkout.
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'postgres', true);
insert into auth.users (id, email) values
  ('ac100000-0000-0000-0000-000000000001', 'patch-merchant-approved@example.invalid'),
  ('ac100000-0000-0000-0000-000000000002', 'patch-merchant-pending@example.invalid'),
  ('ac100000-0000-0000-0000-000000000003', 'patch-buyer@example.invalid'),
  ('ac100000-0000-0000-0000-000000000004', 'patch-admin@example.invalid');

insert into public.profiles (id, name, email, role) values
  ('ac100000-0000-0000-0000-000000000001', 'Patch Approved Merchant', 'ignored@example.invalid', 'merchant'),
  ('ac100000-0000-0000-0000-000000000002', 'Patch Pending Merchant', 'ignored@example.invalid', 'merchant'),
  ('ac100000-0000-0000-0000-000000000003', 'Patch Buyer', 'ignored@example.invalid', 'user'),
  ('ac100000-0000-0000-0000-000000000004', 'Patch Admin', 'ignored@example.invalid', 'admin');

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000003', true);
set local role authenticated;
select throws_ok(
  case when to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is not null
    then $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000002', 'approved', 'Test approval')$$
    else $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000002', 'approved')$$ end,
  'P0001',
  case when to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is not null
    then 'NOT_AUTHORIZED' else 'Only admins can change merchant status.' end,
  'an authenticated non-admin cannot approve a merchant'
);
reset role;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000004', true);
set local role authenticated;
select lives_ok(
  case when to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is not null
    then $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000001', 'approved', 'Test approval')$$
    else $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000001', 'approved')$$ end,
  'fixture admin can approve the test merchant'
);
reset role;

insert into public.products (
  merchant_id, name, description, price, stock,
  original_price, offer_price, category
) values
  ('ac100000-0000-0000-0000-000000000001', 'patch-approved-product', 'test', 10, 6, 12, 10, 'Electronics'),
  ('ac100000-0000-0000-0000-000000000002', 'patch-pending-product', 'test', 10, 6, 12, 10, 'Electronics');

select set_config('test.patch_approved_product_id',
  (select id::text from public.products where name = 'patch-approved-product'), true);
select set_config('test.patch_pending_product_id',
  (select id::text from public.products where name = 'patch-pending-product'), true);
insert into public.cart_items (user_id, product_id, quantity)
values (
  'ac100000-0000-0000-0000-000000000003',
  current_setting('test.patch_approved_product_id')::bigint,
  2
);
select set_config('test.patch_cart_item_id',
  (select id::text from public.cart_items
   where user_id = 'ac100000-0000-0000-0000-000000000003'), true);

-- Authenticated self-approval must fail at the privilege boundary.
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$select public.approve_my_merchant_account()$$,
  case when to_regprocedure('public.approve_my_merchant_account()') is null
    then '42883' else '42501' end,
  null,
  'a pending merchant cannot invoke a missing or revoked self-approval RPC'
);
select is(
  (select merchant_status from public.profiles
   where id = 'ac100000-0000-0000-0000-000000000002'),
  'pending',
  'rejected self-approval leaves the merchant pending'
);
reset role;

-- Pending merchants retain authenticated access to their own listings.
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000002', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products
   where id = current_setting('test.patch_pending_product_id')::bigint),
  1,
  'a pending merchant can still read their own product listing'
);
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products
   where id = current_setting('test.patch_approved_product_id')::bigint),
  1,
  'an approved merchant retains access to their own listing'
);
reset role;

-- Customers see approved listings only; an admin may inspect both rows.
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select is(
  (select count(*)::int from public.products where name like 'patch-%-product'),
  1,
  'customers see the approved product and not the pending product'
);
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000003', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products where name like 'patch-%-product'),
  1,
  'an authenticated customer direct query hides the pending product'
);
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000004', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products where name like 'patch-%-product'),
  2,
  'an admin can inspect approved and pending merchant products'
);
reset role;

-- Suspend the approved seller while the buyer's cart line already exists.
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000004', true);
set local role authenticated;
select lives_ok(
  case when to_regprocedure('public.admin_set_merchant_status(uuid,text,text)') is not null
    then $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000001', 'suspended', 'Test suspension')$$
    else $$select public.admin_set_merchant_status(
      'ac100000-0000-0000-0000-000000000001', 'suspended')$$ end,
  'fixture admin can suspend the test merchant'
);
reset role;

select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select is(
  (select count(*)::int from public.products
   where id = current_setting('test.patch_approved_product_id')::bigint),
  0,
  'customers cannot read the suspended merchant product'
);
reset role;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000001', true);
set local role authenticated;
select is(
  (select count(*)::int from public.products
   where id = current_setting('test.patch_approved_product_id')::bigint),
  1,
  'a suspended merchant retains access to their own listing'
);
reset role;

-- Both cart mutation RPCs and legacy checkout must fail at the table guard.
select set_config('request.jwt.claim.sub', 'ac100000-0000-0000-0000-000000000003', true);
set local role authenticated;
select throws_ok(
  format('select public.update_cart_quantity(%s, 3)',
    current_setting('test.patch_cart_item_id')::bigint),
  'P0001', 'MERCHANT_UNAVAILABLE',
  'a buyer cannot increase a stale cart line after merchant suspension'
);
select throws_ok(
  format('select public.add_to_cart(%s, 1)',
    current_setting('test.patch_approved_product_id')::bigint),
  'P0001', 'MERCHANT_UNAVAILABLE',
  'a buyer cannot add a suspended merchant product to a cart'
);
select throws_ok(
  $$select public.place_demo_order()$$,
  'P0001', 'MERCHANT_UNAVAILABLE',
  'legacy demo checkout rejects a suspended merchant product'
);
reset role;

select is(
  (select count(*)::int from public.orders
   where buyer_id = 'ac100000-0000-0000-0000-000000000003'),
  0,
  'failed legacy checkout rolls back its order header'
);
select is(
  (select stock from public.products
   where id = current_setting('test.patch_approved_product_id')::bigint),
  6,
  'failed legacy checkout does not decrement stock'
);
select is(
  (select count(*)::int from public.cart_items
   where id = current_setting('test.patch_cart_item_id')::bigint),
  1,
  'failed legacy checkout retains the buyer cart line'
);

select * from finish();
rollback;

-- CONCURRENT TWO-SESSION TEST (manual integration test; not run by pgTAP).
-- Run only on a restored legacy GoCart baseline after seeding isolated fixtures:
-- merchant  ac100000-0000-0000-0000-000000000001 (approved)
-- buyer     ac100000-0000-0000-0000-000000000003
-- admin     ac100000-0000-0000-0000-000000000004
-- product   patch-approved-product, with one buyer cart line.
-- Session A: BEGIN; set request.jwt.claim.role=authenticated and sub=admin;
-- SET LOCAL ROLE authenticated; call admin_set_merchant_status(merchant,'suspended');
-- SELECT pg_sleep(5); COMMIT.
-- During the sleep, Session B sets authenticated/sub=buyer, then calls
-- place_demo_order(). It must wait for the profile row lock and then fail with
-- MERCHANT_UNAVAILABLE. Verify no order header, no stock decrement, and the
-- cart row remains. Also run the inverse ordering: checkout completes first,
-- then suspension commits; the result must be a complete order or a complete
-- rejection, never a partial order/stock/cart mutation.
