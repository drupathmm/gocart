begin;

select plan(15);

select has_table('public', 'profiles', 'profiles base table exists');
select has_table('public', 'products', 'products base table exists');
select has_table('public', 'cart_items', 'cart_items base table exists');

select ok(
  (select data_type = 'bigint'
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'products'
     and column_name = 'id'),
  'product IDs stay bigint for current Flutter models'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.cart_items'::regclass
      and contype = 'u'
      and conname = 'cart_items_user_product_key'
  ),
  'a user can have only one cart row per product'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_price_matches_offer'
  ),
  'the legacy price field cannot disagree with the checkout price'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_category_allowed'
  ),
  'database product categories match the Flutter category list'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.products'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.cart_items'::regclass),
  'RLS is enabled on each base table'
);

select ok(
  not has_column_privilege('authenticated', 'public.products', 'stock', 'UPDATE'),
  'authenticated clients cannot directly update product stock'
);

select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'),
  'authenticated clients cannot directly change their role'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Profiles are readable by signed-in users'
      and qual like '%is_current_user_admin%'
  ),
  'profile RLS uses a non-recursive admin check'
);

select ok(
  has_function_privilege('authenticated', 'public.add_to_cart(bigint,integer)', 'EXECUTE'),
  'signed-in users can use the guarded cart function'
);

select ok(
  not has_function_privilege('anon', 'public.is_current_user_admin()', 'EXECUTE'),
  'anonymous clients cannot call the admin-check helper'
);

select ok(
  exists (
    select 1 from storage.buckets
    where id = 'product-images'
      and public is true
      and file_size_limit = 5242880
      and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']::text[]
  ),
  'product image bucket matches the Flutter upload limits'
);

select ok(
  (select count(*) = 3
   from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname in (
       'Public can read product images',
       'Approved merchants upload own product images',
       'Owners and admins delete product images'
     )),
  'product image read/upload/delete policies exist'
);

select * from finish();

rollback;
