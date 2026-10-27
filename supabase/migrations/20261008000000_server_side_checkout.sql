begin;

-- Fail closed before schema changes when legacy order values would otherwise
-- be reinterpreted as provider-paid. The old checkout schema records demo
-- orders as `demo_paid`; that marker is not evidence of a Razorpay capture.
-- Lock the relations before checking so a concurrent legacy checkout cannot
-- insert a row between this preflight and the schema transformations below.
lock table public.orders, public.order_items in access exclusive mode;

do $legacy_order_preflight$
declare
  v_order_item_id smallint;
begin
  if exists (
    select 1
    from public.orders o
    where o.payment_method = 'demo'
       or o.payment_status = 'demo_paid'
       or o.status in ('placed', 'processing')
  ) then
    raise exception 'LEGACY_ORDER_PAYMENT_RECONCILIATION_REQUIRED';
  end if;

  select a.attnum into v_order_item_id
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.order_items'::regclass
    and a.attname = 'id'
    and a.attnum > 0
    and not a.attisdropped;

  if v_order_item_id is null or exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.order_items'::regclass
      and v_order_item_id = any(c.confkey)
  ) then
    raise exception 'ORDER_ITEM_ID_DEPENDENCY_REQUIRES_RECONCILIATION';
  end if;
end;
$legacy_order_preflight$;

-- Evolve demo checkout into server-authoritative orders, offers, and stock.
-- products.id remains bigint (existing catalog); order_items.product_id stays bigint.
-- Direct client writes to orders / order_items / products.stock are revoked.

-- ---------------------------------------------------------------------------
-- orders
-- ---------------------------------------------------------------------------
alter table public.orders
  drop constraint if exists orders_status_check;
alter table public.orders
  drop constraint if exists orders_payment_method_check;
alter table public.orders
  drop constraint if exists orders_payment_status_check;
alter table public.orders
  drop constraint if exists orders_buyer_id_fkey;

alter table public.orders rename column buyer_id to user_id;
alter table public.orders rename column total to total_amount;

alter table public.orders
  alter column total_amount type numeric(10, 2);

alter table public.orders
  add constraint orders_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete cascade;

alter table public.orders
  add column if not exists idempotency_key text;

alter table public.orders
  add column if not exists razorpay_order_id text;

create unique index if not exists orders_idempotency_key_uidx
  on public.orders (idempotency_key)
  where idempotency_key is not null;

create unique index if not exists orders_razorpay_order_id_uidx
  on public.orders (razorpay_order_id)
  where razorpay_order_id is not null;

alter table public.orders
  alter column status set default 'pending';

alter table public.orders
  add constraint orders_status_check
  check (status in (
    'pending',
    'paid',
    'shipped',
    'cancelled',
    'delivered',
    'return_requested',
    'returned'
  ));

alter table public.orders
  add constraint orders_total_amount_nonnegative
  check (total_amount >= 0);

alter table public.orders
  alter column payment_method drop not null;

alter table public.orders
  alter column payment_status drop not null;

alter table public.orders
  alter column payment_method set default 'unpaid';

alter table public.orders
  alter column payment_status set default 'unpaid';

-- ---------------------------------------------------------------------------
-- order_items: preserve its old identity as legacy_id while moving the public
-- primary key to UUID. The Flutter app reads snapshots, not the legacy key.
-- ---------------------------------------------------------------------------
alter table public.order_items
  add column if not exists uuid_id uuid default gen_random_uuid();

update public.order_items
set uuid_id = gen_random_uuid()
where uuid_id is null;

alter table public.order_items
  alter column uuid_id set default gen_random_uuid(),
  alter column uuid_id set not null;

alter table public.order_items rename column id to legacy_id;
alter table public.order_items rename column uuid_id to id;
alter table public.order_items drop constraint if exists order_items_pkey;
alter table public.order_items
  add constraint order_items_pkey primary key (id);

alter table public.order_items
  alter column unit_price type numeric(10, 2);

-- ---------------------------------------------------------------------------
-- offers
-- ---------------------------------------------------------------------------
create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  discount_type text not null check (discount_type in ('percent', 'flat')),
  discount_value numeric not null check (
    discount_value >= 0
    and (discount_type <> 'percent' or discount_value <= 100)
  ),
  max_discount numeric check (max_discount is null or max_discount >= 0),
  min_order numeric check (min_order is null or min_order >= 0),
  valid_from timestamptz,
  valid_to timestamptz,
  usage_limit integer check (usage_limit is null or usage_limit >= 0),
  used_count integer not null default 0 check (used_count >= 0),
  per_user_limit integer not null default 1 check (per_user_limit >= 0),
  is_active boolean not null default true
);

create unique index if not exists offers_code_uidx
  on public.offers (lower(code));

create table if not exists public.offer_redemptions (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.offers (id),
  user_id uuid not null references public.profiles (id),
  order_id uuid not null references public.orders (id),
  discount numeric not null check (discount >= 0),
  created_at timestamptz not null default now(),
  unique (order_id)
);

create index if not exists offer_redemptions_user_offer_idx
  on public.offer_redemptions (user_id, offer_id);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
do $drop_order_writes$
declare
  pol record;
begin
  for pol in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('orders', 'order_items')
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      pol.policyname,
      pol.tablename
    );
  end loop;
end;
$drop_order_writes$;

alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.cart_items enable row level security;
alter table public.products enable row level security;
alter table public.offers enable row level security;
alter table public.offer_redemptions enable row level security;

drop policy if exists "Buyers can view own orders" on public.orders;
create policy "Users can view own orders"
  on public.orders for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Buyers and merchants can view order items" on public.order_items;
create policy "Users can view own order items"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.user_id = (select auth.uid())
    )
  );

drop policy if exists "Users can view own cart" on public.cart_items;
create policy "Users can view own cart"
  on public.cart_items for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Anyone can view products" on public.products;
drop policy if exists "Public can view products" on public.products;
drop policy if exists "Catalog is readable" on public.products;
create policy "Catalog is readable"
  on public.products for select to anon, authenticated
  using (true);

drop policy if exists "Merchants manage own products" on public.products;
create policy "Merchants insert own products"
  on public.products for insert to authenticated
  with check (merchant_id = (select auth.uid()));

create policy "Merchants update own product fields"
  on public.products for update to authenticated
  using (merchant_id = (select auth.uid()))
  with check (merchant_id = (select auth.uid()));

drop policy if exists "Active offers are readable" on public.offers;
create policy "Active offers are readable"
  on public.offers for select to authenticated
  using (is_active = true);

drop policy if exists "Users can view own redemptions" on public.offer_redemptions;
create policy "Users can view own redemptions"
  on public.offer_redemptions for select to authenticated
  using (user_id = (select auth.uid()));

revoke all privileges on table public.orders from anon, authenticated, public;
revoke all privileges on table public.order_items from anon, authenticated, public;
grant select on table public.orders, public.order_items to authenticated;
grant all on table public.orders, public.order_items to postgres;
do $grant_service$
begin
  grant all on table public.orders, public.order_items to service_role;
exception
  when undefined_object then
    null;
end;
$grant_service$;

revoke all privileges on table public.offers from anon, authenticated, public;
grant select on table public.offers to authenticated;

revoke all privileges on table public.offer_redemptions from anon, authenticated, public;
grant select on table public.offer_redemptions to authenticated;

revoke update on table public.products from anon, authenticated;
revoke insert (stock) on table public.products from anon, authenticated;
grant select on table public.products to anon, authenticated;
revoke insert on table public.products from authenticated;
grant insert (
  merchant_id,
  name,
  description,
  original_price,
  offer_price,
  price,
  category,
  image_url
) on table public.products to authenticated;
grant update (
  name,
  description,
  original_price,
  offer_price,
  price,
  category,
  image_url,
  updated_at
) on table public.products to authenticated;

-- ---------------------------------------------------------------------------
-- merchant stock (SECURITY DEFINER) — clients cannot UPDATE products.stock
-- ---------------------------------------------------------------------------
create or replace function public.merchant_set_product_stock(
  p_product_id bigint,
  p_stock integer
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_stock is null or p_stock < 0 then
    raise exception 'INVALID_STOCK';
  end if;

  update public.products
  set stock = p_stock,
      updated_at = now()
  where id = p_product_id
    and merchant_id = v_user;

  if not found then
    raise exception 'PRODUCT_NOT_FOUND';
  end if;
end;
$function$;

revoke all on function public.merchant_set_product_stock(bigint, integer)
  from public, anon, authenticated;
grant execute on function public.merchant_set_product_stock(bigint, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- place_order
-- ---------------------------------------------------------------------------
create or replace function public.place_order(
  p_offer_code text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_existing uuid;
  v_existing_user uuid;
  v_cart_count integer;
  v_cart_ids bigint[];
  v_processed integer := 0;
  v_subtotal numeric(10, 2) := 0;
  v_discount numeric(10, 2) := 0;
  v_line record;
  v_unit numeric(10, 2);
  v_offer public.offers%rowtype;
  v_user_redemptions integer;
  v_code text;
begin
  if v_user is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_user::text));

  if p_idempotency_key is not null and length(trim(p_idempotency_key)) > 0 then
    -- The key is globally unique, so serialize equal keys across users too.
    perform pg_advisory_xact_lock(hashtext(trim(p_idempotency_key)));

    select o.id, o.user_id
      into v_existing, v_existing_user
    from public.orders o
    where o.idempotency_key = trim(p_idempotency_key);

    if v_existing is not null then
      if v_existing_user = v_user then
        return v_existing;
      end if;
      raise exception 'IDEMPOTENCY_CONFLICT';
    end if;
  end if;

  select array_agg(ci.id order by ci.id), count(*)::integer
    into v_cart_ids, v_cart_count
  from public.cart_items ci
  where ci.user_id = v_user;

  if coalesce(v_cart_count, 0) = 0 then
    raise exception 'CART_EMPTY';
  end if;

  -- Match cart RPC lock order (products, then cart rows). Keep this checkout
  -- bound to its original cart snapshot; concurrent additions remain in cart.
  perform p.id
  from public.products p
  join public.cart_items ci on ci.product_id = p.id
  where ci.id = any(v_cart_ids)
    and ci.user_id = v_user
  order by p.id
  for update of p;

  perform ci.id
  from public.cart_items ci
  where ci.id = any(v_cart_ids)
    and ci.user_id = v_user
  order by ci.id
  for update of ci;

  insert into public.orders (
    user_id,
    total_amount,
    status,
    idempotency_key,
    payment_method,
    payment_status
  )
  values (
    v_user,
    0,
    'pending',
    nullif(trim(coalesce(p_idempotency_key, '')), ''),
    'unpaid',
    'unpaid'
  )
  returning id into v_order_id;

  for v_line in
    select ci.product_id, ci.quantity, p.merchant_id, p.name
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.id = any(v_cart_ids)
      and ci.user_id = v_user
    order by ci.product_id
  loop
    update public.products
    set stock = stock - v_line.quantity,
        updated_at = now()
    where id = v_line.product_id
      and stock >= v_line.quantity
    returning coalesce(offer_price, price) into v_unit;

    if not found then
      raise exception 'OUT_OF_STOCK';
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      merchant_id,
      product_name,
      unit_price,
      quantity,
      line_total
    )
    values (
      v_order_id,
      v_line.product_id,
      v_line.merchant_id,
      v_line.name,
      v_unit,
      v_line.quantity,
      round(v_unit * v_line.quantity, 2)
    );

    v_subtotal := v_subtotal + round(v_unit * v_line.quantity, 2);
    v_processed := v_processed + 1;
  end loop;

  if v_processed <> v_cart_count then
    raise exception 'OUT_OF_STOCK';
  end if;

  if p_offer_code is not null and length(trim(p_offer_code)) > 0 then
    v_code := trim(p_offer_code);

    select *
      into v_offer
    from public.offers
    where lower(code) = lower(v_code)
    for update;

    if not found
      or v_offer.is_active is not true
      or v_offer.discount_value < 0
      or (v_offer.discount_type = 'percent' and v_offer.discount_value > 100)
      or (v_offer.valid_from is not null and now() < v_offer.valid_from)
      or (v_offer.valid_to is not null and now() > v_offer.valid_to)
      or (v_offer.min_order is not null and v_subtotal < v_offer.min_order)
    then
      raise exception 'OFFER_NOT_AVAILABLE';
    end if;

    select count(*)::integer
      into v_user_redemptions
    from public.offer_redemptions
    where offer_id = v_offer.id
      and user_id = v_user;

    if v_offer.per_user_limit is not null
      and v_user_redemptions >= v_offer.per_user_limit
    then
      raise exception 'OFFER_NOT_AVAILABLE';
    end if;

    if v_offer.discount_type = 'percent' then
      v_discount := round(v_subtotal * (v_offer.discount_value / 100.0), 2);
    else
      v_discount := round(v_offer.discount_value, 2);
    end if;

    if v_offer.max_discount is not null and v_discount > v_offer.max_discount then
      v_discount := v_offer.max_discount;
    end if;

    if v_discount > v_subtotal then
      raise exception 'OFFER_DISCOUNT_EXCEEDS_SUBTOTAL';
    end if;

    update public.offers
    set used_count = used_count + 1
    where id = v_offer.id
      and (usage_limit is null or used_count < usage_limit);

    if not found then
      raise exception 'OFFER_NOT_AVAILABLE';
    end if;

    insert into public.offer_redemptions (offer_id, user_id, order_id, discount)
    values (v_offer.id, v_user, v_order_id, v_discount);
  end if;

  update public.orders
  set total_amount = greatest(v_subtotal - v_discount, 0)
  where id = v_order_id;

  delete from public.cart_items
  where id = any(v_cart_ids)
    and user_id = v_user;

  return v_order_id;
end;
$function$;

revoke all on function public.place_order(text, text) from public, anon;
grant execute on function public.place_order(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- change_order_status
-- ---------------------------------------------------------------------------
create or replace function public.change_order_status(
  p_order_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
  v_current text;
  v_owner uuid;
  v_allowed boolean := false;
  v_is_service boolean := v_role = 'service_role';
begin
  if p_new_status is null then
    raise exception 'INVALID_TRANSITION';
  end if;

  select status, user_id
    into v_current, v_owner
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  if v_current = p_new_status then
    return;
  end if;

  v_allowed :=
    (v_current = 'pending' and p_new_status = 'paid')
    or (v_current = 'paid' and p_new_status = 'shipped')
    or (v_current = 'shipped' and p_new_status = 'delivered')
    or (v_current = 'delivered' and p_new_status = 'return_requested')
    or (v_current in ('pending', 'paid') and p_new_status = 'cancelled');

  if not v_allowed then
    raise exception 'INVALID_TRANSITION';
  end if;

  if p_new_status = 'cancelled' then
    if not v_is_service and (v_user is null or v_user <> v_owner) then
      raise exception 'NOT_AUTHORIZED';
    end if;
  elsif not v_is_service then
    raise exception 'NOT_AUTHORIZED';
  end if;

  if p_new_status = 'cancelled' then
    update public.products p
    set stock = p.stock + oi.quantity,
        updated_at = now()
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.product_id = p.id;

    update public.offers o
    set used_count = greatest(o.used_count - 1, 0)
    from public.offer_redemptions r
    where r.order_id = p_order_id
      and r.offer_id = o.id;

    delete from public.offer_redemptions
    where order_id = p_order_id;
  end if;

  update public.orders
  set status = p_new_status,
      payment_status = case
        when p_new_status = 'paid' then 'paid'
        when p_new_status = 'cancelled' then 'cancelled'
        else payment_status
      end,
      payment_method = case
        when p_new_status = 'paid' then coalesce(payment_method, 'razorpay')
        else payment_method
      end
  where id = p_order_id;
end;
$function$;

revoke all on function public.change_order_status(uuid, text)
  from public, anon, authenticated;
grant execute on function public.change_order_status(uuid, text)
  to service_role;

create or replace function public.cancel_own_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  perform public.change_order_status(p_order_id, 'cancelled');
end;
$function$;

revoke all on function public.cancel_own_order(uuid) from public, anon;
grant execute on function public.cancel_own_order(uuid) to authenticated;

-- Keep the old RPC name as a thin wrapper for any leftover clients.
create or replace function public.place_demo_order()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_id uuid;
  v_total numeric(10, 2);
begin
  v_id := public.place_order(null, null);
  select total_amount into v_total from public.orders where id = v_id;
  return jsonb_build_object(
    'order_id', v_id,
    'total', v_total,
    'total_amount', v_total,
    'item_count', (
      select coalesce(sum(quantity), 0) from public.order_items where order_id = v_id
    )
  );
end;
$function$;

commit;
