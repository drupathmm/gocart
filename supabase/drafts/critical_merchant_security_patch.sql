-- REVIEW-ONLY patch for the previously verified legacy GoCart schema.
-- Deliberately outside supabase/migrations; this file is NOT applied.
-- It leaves existing products, carts, orders, payment states, login, and
-- reinstatement requests untouched.

begin;

do $preflight$
declare
  v_required record;
begin
  for v_required in
    select * from (values
      ('public.profiles', 'id', 'uuid'),
      ('public.profiles', 'name', 'text'),
      ('public.profiles', 'email', 'text'),
      ('public.profiles', 'role', 'text'),
      ('public.profiles', 'merchant_status', 'text'),
      ('public.profiles', 'created_at', 'timestamp with time zone'),
      ('public.products', 'id', 'bigint'),
      ('public.products', 'merchant_id', 'uuid'),
      ('public.cart_items', 'product_id', 'bigint'),
      ('public.cart_items', 'id', 'bigint'),
      ('public.cart_items', 'user_id', 'uuid'),
      ('public.cart_items', 'quantity', 'integer'),
      ('public.products', 'stock', 'integer'),
      ('public.products', 'offer_price', 'numeric(10,2)'),
      ('public.products', 'name', 'text'),
      ('public.order_items', 'product_id', 'bigint'),
      ('public.order_items', 'merchant_id', 'uuid'),
      ('public.order_items', 'order_id', 'uuid'),
      ('public.order_items', 'product_name', 'text'),
      ('public.order_items', 'unit_price', 'numeric(12,2)'),
      ('public.order_items', 'quantity', 'integer'),
      ('public.order_items', 'line_total', 'numeric(12,2)'),
      ('public.orders', 'id', 'uuid'),
      ('public.orders', 'buyer_id', 'uuid'),
      ('public.orders', 'status', 'text'),
      ('public.orders', 'payment_method', 'text'),
      ('public.orders', 'payment_status', 'text'),
      ('public.orders', 'total', 'numeric(12,2)')
    ) as required(table_name, column_name, type_name)
  loop
    if to_regclass(v_required.table_name) is null
       or not exists (
         select 1 from pg_catalog.pg_attribute a
         where a.attrelid = to_regclass(v_required.table_name)
           and a.attname = v_required.column_name
           and a.attnum > 0 and not a.attisdropped
           and pg_catalog.format_type(a.atttypid, a.atttypmod) = v_required.type_name
       ) then
      raise exception 'MERCHANT_SECURITY_SCHEMA_MISMATCH: %.% expected %',
        v_required.table_name, v_required.column_name, v_required.type_name;
    end if;
  end loop;

  if to_regprocedure('auth.uid()') is null then
    raise exception 'MERCHANT_SECURITY_REQUIRED_FUNCTION_MISSING';
  end if;
  if (select count(*) from pg_catalog.pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = 'approve_my_merchant_account') > 1 then
    raise exception 'MERCHANT_SECURITY_UNEXPECTED_SELF_APPROVAL_OVERLOAD';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid = 'public.products'::regclass and c.relrowsecurity
  ) then
    raise exception 'MERCHANT_SECURITY_PRODUCTS_RLS_DISABLED';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_policies p
    where p.schemaname = 'public' and p.tablename = 'products'
      and p.cmd = 'SELECT' and p.permissive = 'PERMISSIVE'
  ) then
    raise exception 'MERCHANT_SECURITY_NO_EXISTING_PRODUCT_SELECT_POLICY';
  end if;
  -- SECURITY DEFINER functions must be able to read profiles without being
  -- filtered by its RLS policy; do not install if this execution identity
  -- would recurse through or be filtered by profiles RLS.
  if not exists (
    select 1 from pg_catalog.pg_roles r
    join pg_catalog.pg_class c on c.oid = 'public.profiles'::regclass
    where r.rolname = current_user
      and (r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
  ) then
    raise exception 'MERCHANT_SECURITY_DEFINER_OWNER_CANNOT_BYPASS_PROFILE_RLS';
  end if;

  if exists (
       select 1 from pg_catalog.pg_namespace n
       where n.nspname = 'gocart_private'
     )
     or to_regprocedure('public.guard_active_merchant_cart_item()') is not null
     or to_regprocedure('public.guard_active_merchant_order_item()') is not null
     or exists (
       select 1 from pg_catalog.pg_policy p
       where p.polrelid = 'public.products'::regclass
         and p.polname = 'Merchant approval required for product reads'
     )
     or exists (
       select 1 from pg_catalog.pg_trigger t
       where not t.tgisinternal and t.tgname in (
         'cart_items_require_approved_merchant_insert',
         'cart_items_require_approved_merchant_update',
         'order_items_require_approved_merchant'
       )
     )
     or exists (
       select 1 from pg_catalog.pg_trigger t
       where not t.tgisinternal
         and t.tgrelid in ('public.cart_items'::regclass,
                           'public.order_items'::regclass)
     ) then
    raise exception 'MERCHANT_SECURITY_PATCH_OBJECT_CONFLICT';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.add_to_cart(bigint,integer)'::regprocedure
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.update_cart_quantity(bigint,integer)'::regprocedure
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.place_demo_order()'::regprocedure
  ) then
    raise exception 'MERCHANT_SECURITY_LEGACY_WRITE_PATH_MISMATCH';
  end if;
end;
$preflight$;

-- The preceding merchant-authorization repair may already have removed this
-- function. If it remains, revoke client execution without assuming presence.
do $revoke_legacy_approval$
begin
  if to_regprocedure('public.approve_my_merchant_account()') is not null then
    execute 'revoke all on function public.approve_my_merchant_account() from public, anon, authenticated, service_role';
  end if;
end;
$revoke_legacy_approval$;

-- Keep ordinary profile editing limited to the display name. Merchant status
-- and role changes stay behind the server-side admin workflow; signup's
-- existing profile trigger remains responsible for assigning pending status.
revoke update on table public.profiles
  from public, anon, authenticated, service_role;
revoke update (id, name, email, role, created_at, merchant_status)
  on table public.profiles from public, anon, authenticated, service_role;
grant update (name) on table public.profiles to authenticated;

-- The definer helper exposes only a boolean. Merchants retain access to their
-- own listings while signed in; customers require approved merchant status.
create schema gocart_private;
revoke all on schema gocart_private from public, anon, authenticated;
grant usage on schema gocart_private to anon, authenticated;

create function gocart_private.product_visible_to_requester(p_merchant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.profiles p
    where p.id = p_merchant_id and p.role = 'merchant'
      and (
        p.merchant_status = 'approved'
        or p.id = auth.uid()
        or exists (
          select 1 from public.profiles a
          where a.id = auth.uid() and a.role = 'admin'
        )
      )
  );
$function$;
revoke all on function gocart_private.product_visible_to_requester(uuid)
  from public, anon, authenticated, service_role;
grant execute on function gocart_private.product_visible_to_requester(uuid)
  to anon, authenticated;

-- A restrictive policy prevents any permissive USING (true) policy from
-- exposing suspended products, while retaining owner/admin reads.
create policy "Merchant approval required for product reads"
  on public.products as restrictive for select to public
  using (gocart_private.product_visible_to_requester(merchant_id));

create function public.guard_active_merchant_cart_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_merchant_id uuid; v_role text; v_status text;
begin
  select p.merchant_id into v_merchant_id
  from public.products p where p.id = new.product_id;
  if not found then raise exception 'MERCHANT_UNAVAILABLE'; end if;

  -- Serialize cart writes with admin merchant status changes.
  select p.role, p.merchant_status into v_role, v_status
  from public.profiles p where p.id = v_merchant_id for share;
  if not found or v_role is distinct from 'merchant'
     or v_status is distinct from 'approved' then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_active_merchant_cart_item()
  from public, anon, authenticated, service_role;
create trigger cart_items_require_approved_merchant_insert
  before insert on public.cart_items
  for each row execute function public.guard_active_merchant_cart_item();
create trigger cart_items_require_approved_merchant_update
  before update of product_id, quantity on public.cart_items
  for each row execute function public.guard_active_merchant_cart_item();

create function public.guard_active_merchant_order_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_product_merchant_id uuid; v_role text; v_status text;
begin
  if new.product_id is null then raise exception 'MERCHANT_UNAVAILABLE'; end if;
  select p.merchant_id into v_product_merchant_id
  from public.products p where p.id = new.product_id;
  if not found or v_product_merchant_id is distinct from new.merchant_id then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;

  -- Failure aborts the enclosing checkout transaction, including its order
  -- and stock changes. Existing order rows are never touched.
  select p.role, p.merchant_status into v_role, v_status
  from public.profiles p where p.id = v_product_merchant_id for share;
  if not found or v_role is distinct from 'merchant'
     or v_status is distinct from 'approved' then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;
  return new;
end;
$function$;
revoke all on function public.guard_active_merchant_order_item()
  from public, anon, authenticated, service_role;
create trigger order_items_require_approved_merchant
  before insert on public.order_items
  for each row execute function public.guard_active_merchant_order_item();

-- Replace the legacy demo checkout body only after the preflight proves its
-- bigint product/cart contract. Merchant profiles are locked in UUID order
-- after product and cart rows, and before inserting orders, decrementing stock
-- or deleting cart rows. A concurrent suspension therefore either waits for
-- a complete checkout or causes checkout to abort atomically.
create or replace function public.place_demo_order()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_buyer_id uuid := (select auth.uid());
  v_order_id uuid;
  v_cart_ids bigint[];
  v_cart_count integer;
  v_item_count integer := 0;
  v_merchant_count integer;
  v_locked_merchant_count integer;
  v_total numeric(12, 2) := 0;
  v_line record;
begin
  if v_buyer_id is null then
    raise exception 'You must be signed in to place an order.';
  end if;

  select array_agg(ci.id order by ci.id), count(*)::integer
    into v_cart_ids, v_cart_count
  from public.cart_items ci where ci.user_id = v_buyer_id;
  if coalesce(v_cart_count, 0) = 0 then
    raise exception 'Your cart is empty.';
  end if;

  -- Lock products, then cart rows, then merchant profiles. All multi-row
  -- locks use stable ordering so concurrent checkouts share the same order.
  perform p.id
  from public.products p
  join public.cart_items ci on ci.product_id = p.id
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
  order by p.id for update of p;

  perform ci.id
  from public.cart_items ci
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
  order by ci.id for update of ci;

  select count(distinct p.merchant_id)::integer
    into v_merchant_count
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id;

  perform pr.id
  from public.profiles pr
  join (
    select distinct p.merchant_id
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
  ) merchants on merchants.merchant_id = pr.id
  order by pr.id for share of pr;

  get diagnostics v_locked_merchant_count = row_count;
  if v_locked_merchant_count <> v_merchant_count then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;
  if exists (
    select 1
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    join public.profiles pr on pr.id = p.merchant_id
    where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
      and (pr.role is distinct from 'merchant'
        or pr.merchant_status is distinct from 'approved')
  ) then
    raise exception 'MERCHANT_UNAVAILABLE';
  end if;

  for v_line in
    select ci.id, ci.product_id, ci.quantity, p.merchant_id, p.name,
           p.offer_price, p.stock
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
    order by p.id
  loop
    if v_line.quantity <= 0 then
      raise exception 'A cart item has an invalid quantity.';
    end if;
    if v_line.stock < v_line.quantity then
      raise exception 'Not enough stock for "%".', v_line.name;
    end if;
    v_total := v_total + round(v_line.offer_price * v_line.quantity, 2);
    v_item_count := v_item_count + 1;
  end loop;

  if v_item_count <> v_cart_count then
    raise exception 'A product in your cart is no longer available.';
  end if;
  if v_total <= 0 then
    raise exception 'The order total must be greater than zero.';
  end if;

  -- This remains explicitly demo checkout. It does not assert Razorpay capture.
  insert into public.orders (buyer_id, status, payment_method, payment_status, total)
  values (v_buyer_id, 'placed', 'demo', 'demo_paid', v_total)
  returning id into v_order_id;

  insert into public.order_items (
    order_id, product_id, merchant_id, product_name,
    unit_price, quantity, line_total
  )
  select v_order_id, p.id, p.merchant_id, p.name,
         p.offer_price, ci.quantity, round(p.offer_price * ci.quantity, 2)
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id;

  update public.products p
  set stock = p.stock - ci.quantity, updated_at = now()
  from public.cart_items ci
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id
    and ci.product_id = p.id;

  delete from public.cart_items ci
  where ci.id = any(v_cart_ids) and ci.user_id = v_buyer_id;

  return jsonb_build_object(
    'order_id', v_order_id, 'total', v_total, 'item_count', v_item_count
  );
end;
$function$;
revoke all on function public.place_demo_order() from public, anon, authenticated;
grant execute on function public.place_demo_order() to authenticated;

do $postflight$
begin
  if exists (
       select 1 from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.approve_my_merchant_account()')
         and (
           has_function_privilege('authenticated',p.oid,'EXECUTE')
           or has_function_privilege('anon',p.oid,'EXECUTE')
           or has_function_privilege('service_role',p.oid,'EXECUTE')
           or exists (
             select 1 from pg_catalog.aclexplode(
               coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))
             ) a where a.grantee=0 and a.privilege_type='EXECUTE'
           )
         )
     ) then
    raise exception 'MERCHANT_SECURITY_SELF_APPROVAL_STILL_EXECUTABLE';
  end if;
  if has_column_privilege('authenticated', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
     or has_column_privilege('anon', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('anon', 'public.profiles', 'role', 'UPDATE')
     or has_column_privilege('service_role', 'public.profiles', 'merchant_status', 'UPDATE')
     or has_column_privilege('service_role', 'public.profiles', 'role', 'UPDATE') then
    raise exception 'MERCHANT_SECURITY_DIRECT_PROFILE_STATUS_UPDATE_STILL_ALLOWED';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_attribute a
    cross join (values ('anon'), ('authenticated'), ('service_role')) r(role_name)
    where a.attrelid = 'public.profiles'::regclass
      and a.attnum > 0 and not a.attisdropped and a.attname <> 'name'
      and has_column_privilege(r.role_name, 'public.profiles', a.attname, 'UPDATE')
  ) then
    raise exception 'MERCHANT_SECURITY_NON_NAME_PROFILE_UPDATE_STILL_ALLOWED';
  end if;
  if not has_column_privilege('authenticated', 'public.profiles', 'name', 'UPDATE') then
    raise exception 'MERCHANT_SECURITY_PROFILE_NAME_EDIT_NOT_GRANTED';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_policy p
    where p.polrelid = 'public.products'::regclass
      and p.polname = 'Merchant approval required for product reads'
      and not p.polpermissive and p.polcmd = 'r'
  ) then
    raise exception 'MERCHANT_SECURITY_PRODUCT_RESTRICTION_MISSING';
  end if;
  if (select count(*) from pg_catalog.pg_trigger t
      where not t.tgisinternal and t.tgenabled = 'O'
        and t.tgname in (
          'cart_items_require_approved_merchant_insert',
          'cart_items_require_approved_merchant_update',
          'order_items_require_approved_merchant'
        )) <> 3 then
    raise exception 'MERCHANT_SECURITY_WRITE_GUARDS_MISSING';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    join pg_catalog.pg_class c on c.oid = 'public.profiles'::regclass
    where p.oid in (
      'gocart_private.product_visible_to_requester(uuid)'::regprocedure,
      'public.guard_active_merchant_cart_item()'::regprocedure,
      'public.guard_active_merchant_order_item()'::regprocedure
    )
      and not (r.rolbypassrls or (c.relowner = r.oid and not c.relforcerowsecurity))
  ) then
    raise exception 'MERCHANT_SECURITY_DEFINER_OWNER_CANNOT_BYPASS_PROFILE_RLS';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid in (
      'gocart_private.product_visible_to_requester(uuid)'::regprocedure,
      'public.guard_active_merchant_cart_item()'::regprocedure,
      'public.guard_active_merchant_order_item()'::regprocedure
    )
      and (not p.prosecdef or not (p.proconfig @> array['search_path=""']))
  ) or has_function_privilege(
    'anon', 'public.guard_active_merchant_cart_item()', 'EXECUTE'
  ) or has_function_privilege(
    'authenticated', 'public.guard_active_merchant_cart_item()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.guard_active_merchant_order_item()', 'EXECUTE'
  ) or has_function_privilege(
    'authenticated', 'public.guard_active_merchant_order_item()', 'EXECUTE'
  ) then
    raise exception 'MERCHANT_SECURITY_FUNCTION_HARDENING_FAILED';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) a
    where p.oid in (
      'gocart_private.product_visible_to_requester(uuid)'::regprocedure,
      'public.guard_active_merchant_cart_item()'::regprocedure,
      'public.guard_active_merchant_order_item()'::regprocedure
    )
      and (a.grantee = 0 or a.grantee = 'service_role'::regrole)
      and a.privilege_type = 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'gocart_private.product_visible_to_requester(uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.guard_active_merchant_cart_item()', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.guard_active_merchant_order_item()', 'EXECUTE'
  ) then
    raise exception 'MERCHANT_SECURITY_HELPER_PRIVILEGE_LEAK';
  end if;
end;
$postflight$;

commit;
