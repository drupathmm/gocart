begin;

-- A checkout reservation is created in the same transaction as the pending
-- order. Cart rows remain the buyer's cart until verified payment consumes
-- the reservation. This migration is additive and does not rewrite checkout.
create table public.checkout_reservations (
  order_id uuid primary key
    references public.orders (id) on delete restrict,
  state text not null default 'active'
    check (state in ('active', 'consumed', 'released')),
  source text not null default 'checkout'
    check (source in ('checkout', 'legacy')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  released_at timestamptz,
  released_by uuid,
  release_reason text,
  check (
    (state = 'active' and consumed_at is null and released_at is null)
    or (state = 'consumed' and consumed_at is not null and released_at is null)
    or (state = 'released' and released_at is not null and consumed_at is null)
  )
);

create table public.checkout_reservation_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null
    references public.checkout_reservations (order_id) on delete restrict,
  order_item_id uuid not null unique
    references public.order_items (id) on delete restrict,
  cart_item_id bigint
    references public.cart_items (id) on delete set null,
  product_id bigint not null
    references public.products (id) on delete restrict,
  quantity integer not null check (quantity > 0),
  state text not null default 'active'
    check (state in ('active', 'consumed', 'released')),
  created_at timestamptz not null default now(),
  unique (order_id, cart_item_id)
);

create index checkout_reservations_state_expiry_idx
  on public.checkout_reservations (expires_at, order_id)
  where state = 'active';
create index checkout_reservation_items_order_idx
  on public.checkout_reservation_items (order_id, product_id);
create index checkout_reservation_items_cart_active_idx
  on public.checkout_reservation_items (cart_item_id)
  where state = 'active' and cart_item_id is not null;

-- A cart line may have only one active checkout reservation. The unique index
-- is the final race-safe boundary even if two different idempotency keys are
-- submitted concurrently.
create unique index checkout_reservation_items_one_active_cart_line_uidx
  on public.checkout_reservation_items (cart_item_id)
  where state = 'active' and cart_item_id is not null;

-- Preserve offer-redemption history when an unpaid checkout is released.
-- offer_redemptions remains the active/consumed quota ledger used by the
-- existing checkout RPC's per-user count.
create table public.offer_redemption_history (
  redemption_id uuid primary key,
  offer_id uuid not null,
  user_id uuid not null,
  order_id uuid not null,
  discount numeric not null,
  redeemed_at timestamptz not null,
  archived_at timestamptz not null default now(),
  archived_by uuid,
  archive_reason text not null
);

alter table public.checkout_reservations enable row level security;
alter table public.checkout_reservation_items enable row level security;
alter table public.offer_redemption_history enable row level security;

revoke all on public.checkout_reservations,
  public.checkout_reservation_items,
  public.offer_redemption_history
  from public, anon, authenticated, service_role;

-- Pending orders already present at migration time have already had stock
-- reserved by the old checkout RPC. Backfill only ledger rows; do not touch
-- stock, carts, orders, payment attempts, or offer counters here.
do $reservation_backfill_preflight$
begin
  if exists (
    select 1
    from public.orders o
    where o.status = 'pending'
      and o.payment_status = 'unpaid'
      and not exists (
        select 1 from public.order_items oi where oi.order_id = o.id
      )
  ) then
    raise exception 'CHECKOUT_RESERVATION_PREFLIGHT: pending unpaid order has no order items';
  end if;

  if exists (
    select 1
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    left join public.products p on p.id = oi.product_id
    where o.status = 'pending'
      and o.payment_status = 'unpaid'
      and (oi.product_id is null or p.id is null or oi.quantity is null or oi.quantity <= 0)
  ) then
    raise exception 'CHECKOUT_RESERVATION_PREFLIGHT: pending unpaid order item cannot be safely reserved';
  end if;
end;
$reservation_backfill_preflight$;

insert into public.checkout_reservations (order_id, state, source)
select o.id, 'active', 'legacy'
from public.orders o
where o.status = 'pending'
  and o.payment_status = 'unpaid'
on conflict (order_id) do nothing;

insert into public.checkout_reservation_items (
  order_id, order_item_id, cart_item_id, product_id, quantity, state
)
select r.order_id, oi.id, null, oi.product_id, oi.quantity, r.state
from public.checkout_reservations r
join public.order_items oi on oi.order_id = r.order_id
where r.source = 'legacy'
  and r.state = 'active'
on conflict (order_item_id) do nothing;

create or replace function public.create_checkout_reservation_for_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'pending' and new.payment_status = 'unpaid' then
    insert into public.checkout_reservations (order_id, state, source)
    values (new.id, 'active', 'checkout')
    on conflict (order_id) do nothing;
  end if;
  return new;
end;
$function$;

create or replace function public.attach_checkout_reservation_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source text;
  v_user_id uuid;
  v_cart_item_id bigint;
  v_cart_quantity integer;
begin
  select r.source, o.user_id
    into v_source, v_user_id
  from public.checkout_reservations r
  join public.orders o on o.id = r.order_id
  where r.order_id = new.order_id and r.state = 'active';

  if not found then
    return new;
  end if;

  -- Legacy pending orders have no trustworthy link to the original cart row:
  -- their old checkout deleted it. Keep their exact order-item snapshot, but
  -- do not attach a newer cart row that may have been added later.
  if v_source = 'legacy' then
    return new;
  end if;

  if new.product_id is null or new.quantity is null or new.quantity <= 0 then
    raise exception 'CHECKOUT_RESERVATION_INVALID_ORDER_ITEM';
  end if;

  select ci.id, ci.quantity
    into v_cart_item_id, v_cart_quantity
  from public.cart_items ci
  where ci.user_id = v_user_id and ci.product_id = new.product_id
  for update;

  if not found then
    raise exception 'CHECKOUT_RESERVATION_CART_ITEM_MISSING';
  end if;

  if v_cart_quantity <> new.quantity then
    raise exception 'CHECKOUT_RESERVATION_QUANTITY_MISMATCH';
  end if;

  begin
    insert into public.checkout_reservation_items (
      order_id, order_item_id, cart_item_id, product_id, quantity, state
    ) values (
      new.order_id, new.id, v_cart_item_id, new.product_id,
      new.quantity, 'active'
    );
  exception
    when unique_violation then
      raise exception 'CHECKOUT_QUANTITY_ALREADY_RESERVED';
  end;

  return new;
end;
$function$;

create or replace function public.preserve_reserved_cart_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if exists (
    select 1
    from public.checkout_reservation_items ri
    where ri.cart_item_id = old.id and ri.state = 'active'
  ) then
    -- place_order still issues its historical DELETE. Suppress deletion for
    -- reserved lines so the checkout transaction can complete without losing
    -- the buyer's cart. Direct deletes of a reserved line are also harmless.
    return null;
  end if;
  return old;
end;
$function$;

create or replace function public.guard_reserved_cart_quantity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reserved integer;
begin
  select coalesce(sum(ri.quantity), 0)::integer
    into v_reserved
  from public.checkout_reservation_items ri
  where ri.cart_item_id = old.id and ri.state = 'active';

  if new.quantity < v_reserved then
    raise exception 'CART_QUANTITY_RESERVED';
  end if;
  return new;
end;
$function$;

create trigger orders_create_checkout_reservation
after insert on public.orders
for each row execute function public.create_checkout_reservation_for_order();

create trigger order_items_attach_checkout_reservation
after insert on public.order_items
for each row execute function public.attach_checkout_reservation_item();

create trigger cart_items_preserve_checkout_reservation
before delete on public.cart_items
for each row execute function public.preserve_reserved_cart_item();

create trigger cart_items_guard_reserved_quantity
before update of quantity on public.cart_items
for each row execute function public.guard_reserved_cart_quantity();

create or replace function public.archive_offer_redemption_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.offer_redemption_history (
    redemption_id, offer_id, user_id, order_id, discount, redeemed_at,
    archived_by, archive_reason
  ) values (
    old.id, old.offer_id, old.user_id, old.order_id, old.discount,
    old.created_at, auth.uid(),
    coalesce(
      nullif(pg_catalog.current_setting('gocart.offer_redemption_archive_reason', true), ''),
      'redemption_removed'
    )
  )
  on conflict (redemption_id) do nothing;
  return old;
end;
$function$;

create trigger offer_redemptions_archive_delete
before delete on public.offer_redemptions
for each row execute function public.archive_offer_redemption_before_delete();

create or replace function public.sync_checkout_reservation_item_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.state = 'active' and new.state in ('consumed', 'released') then
    update public.checkout_reservation_items
    set state = new.state
    where order_id = new.order_id and state = 'active';
  elsif old.state is distinct from new.state then
    raise exception 'INVALID_CHECKOUT_RESERVATION_TRANSITION';
  end if;
  return new;
end;
$function$;

create trigger checkout_reservations_sync_items
after update of state on public.checkout_reservations
for each row execute function public.sync_checkout_reservation_item_state();

create or replace function public.consume_checkout_reservation(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation public.checkout_reservations%rowtype;
  v_order public.orders%rowtype;
  v_line record;
  v_cart_quantity integer;
begin
  select * into v_order
  from public.orders o
  where o.id = p_order_id;
  if not found or v_order.status <> 'paid' or v_order.payment_status <> 'paid' then
    raise exception 'CHECKOUT_RESERVATION_REQUIRES_VERIFIED_PAYMENT';
  end if;

  select * into v_reservation
  from public.checkout_reservations r
  where r.order_id = p_order_id
  for update;
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_FOUND'; end if;
  if v_reservation.state = 'consumed' then return; end if;
  if v_reservation.state <> 'active' then
    raise exception 'CHECKOUT_RESERVATION_NOT_ACTIVE';
  end if;

  update public.checkout_reservations
  set state = 'consumed', consumed_at = now()
  where order_id = p_order_id and state = 'active';
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_ACTIVE'; end if;

  -- Only current reservations have cart links. Legacy orders have no reliable
  -- original cart-row identity, so their order-item snapshots are not applied
  -- to a possibly newer cart.
  for v_line in
    select ri.cart_item_id, sum(ri.quantity)::integer as quantity
    from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.cart_item_id is not null
    group by ri.cart_item_id
    order by ri.cart_item_id
  loop
    select ci.quantity into v_cart_quantity
    from public.cart_items ci
    where ci.id = v_line.cart_item_id and ci.user_id = v_order.user_id
    for update;

    if not found or v_cart_quantity < v_line.quantity then
      raise exception 'CHECKOUT_RESERVATION_CART_INVARIANT_FAILED';
    end if;

    if v_cart_quantity = v_line.quantity then
      delete from public.cart_items
      where id = v_line.cart_item_id and user_id = v_order.user_id;
    else
      update public.cart_items
      set quantity = quantity - v_line.quantity
      where id = v_line.cart_item_id and user_id = v_order.user_id;
    end if;
  end loop;

end;
$function$;

create or replace function public.consume_checkout_reservation_after_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'paid' and new.payment_status = 'paid'
     and (old.status is distinct from 'paid'
          or old.payment_status is distinct from 'paid') then
    perform public.consume_checkout_reservation(new.id);
  end if;
  return new;
end;
$function$;

create trigger orders_consume_checkout_reservation
after update of status, payment_status on public.orders
for each row execute function public.consume_checkout_reservation_after_payment();

create or replace function public.guard_checkout_order_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation_state text;
  v_attempt_id uuid;
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    if old.status = 'paid' or old.payment_status = 'paid'
       or new.payment_status = 'paid' then
      raise exception 'PAYMENT_ALREADY_CAPTURED';
    end if;
    if new.payment_status is distinct from 'cancelled' then
      raise exception 'CHECKOUT_CANCELLATION_STATE_MISMATCH';
    end if;

    select r.state into v_reservation_state
    from public.checkout_reservations r
    where r.order_id = new.id;
    if v_reservation_state is distinct from 'released' then
      raise exception 'CHECKOUT_RESERVATION_RELEASE_REQUIRED';
    end if;

    select a.id into v_attempt_id
    from public.razorpay_payment_attempts a
    where a.order_id = new.id;
    if found then
      raise exception 'PAYMENT_RECONCILIATION_REQUIRED';
    end if;
  end if;
  return new;
end;
$function$;

create trigger orders_guard_checkout_cancellation
before update of status, payment_status on public.orders
for each row execute function public.guard_checkout_order_cancellation();

create or replace function public.release_checkout_reservation(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_reservation public.checkout_reservations%rowtype;
  v_attempt_id uuid;
  v_offer_id uuid;
  v_offer_used_count integer;
  v_line record;
  v_role text := coalesce(auth.role(), '');
  v_user_id uuid := auth.uid();
begin
  select * into v_order
  from public.orders o
  where o.id = p_order_id
  for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if v_role <> 'service_role'
     and (v_user_id is null or v_user_id <> v_order.user_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_reservation
  from public.checkout_reservations r
  where r.order_id = p_order_id
  for update;
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_FOUND'; end if;

  if v_reservation.state = 'released' and v_order.status = 'cancelled' then
    return false;
  end if;
  if v_reservation.state = 'consumed'
     or v_order.status = 'paid'
     or v_order.payment_status = 'paid' then
    raise exception 'PAYMENT_ALREADY_CAPTURED';
  end if;
  if v_reservation.state <> 'active'
     or v_order.status <> 'pending'
     or v_order.payment_status <> 'unpaid' then
    raise exception 'CHECKOUT_RESERVATION_NOT_RELEASABLE';
  end if;

  if v_reservation.source = 'legacy' then
    -- Older checkout code did not persist a provider attempt before sending
    -- every possible payment request. An absent attempt row therefore cannot
    -- establish payment finality for a legacy order.
    raise exception 'LEGACY_CHECKOUT_REQUIRES_RECONCILIATION';
  end if;

  -- The provider attempt is claimed and persisted before any provider request.
  -- Any attempt therefore makes payment finality ambiguous here. No timeout,
  -- client callback, or unverified status is accepted as proof of nonpayment.
  select a.id into v_attempt_id
  from public.razorpay_payment_attempts a
  where a.order_id = p_order_id
  for update;
  if found then raise exception 'PAYMENT_RECONCILIATION_REQUIRED'; end if;

  if not exists (
    select 1 from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
  ) then
    raise exception 'CHECKOUT_RESERVATION_ITEMS_MISSING';
  end if;

  -- Lock all affected products in a stable order before restoring stock.
  for v_line in
    select p.id
    from public.products p
    join (
      select ri.product_id
      from public.checkout_reservation_items ri
      where ri.order_id = p_order_id and ri.state = 'active'
      group by ri.product_id
    ) reserved on reserved.product_id = p.id
    order by p.id
    for update of p
  loop
    null;
  end loop;

  update public.products p
  set stock = p.stock + reserved.quantity,
      updated_at = now()
  from (
    select ri.product_id, sum(ri.quantity)::integer as quantity
    from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
    group by ri.product_id
  ) reserved
  where p.id = reserved.product_id;

  select r.offer_id into v_offer_id
  from public.offer_redemptions r
  where r.order_id = p_order_id
  for update;
  if found then
    select o.used_count into v_offer_used_count
    from public.offers o
    where o.id = v_offer_id
    for update;
    if not found or v_offer_used_count < 1 then
      raise exception 'OFFER_RESERVATION_INVARIANT_FAILED';
    end if;
    update public.offers
    set used_count = used_count - 1
    where id = v_offer_id;
    perform pg_catalog.set_config(
      'gocart.offer_redemption_archive_reason',
      'checkout_reservation_released',
      true
    );
    delete from public.offer_redemptions where order_id = p_order_id;
  end if;

  update public.checkout_reservations
  set state = 'released',
      released_at = now(),
      released_by = v_user_id,
      release_reason = case
        when v_role = 'service_role' then 'service_release_without_payment_attempt'
        else 'buyer_cancelled_without_payment_attempt'
      end
  where order_id = p_order_id and state = 'active';
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_ACTIVE'; end if;

  update public.orders
  set status = 'cancelled', payment_status = 'cancelled'
  where id = p_order_id;

  return true;
end;
$function$;

revoke all on function public.release_checkout_reservation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.release_checkout_reservation(uuid)
  to authenticated, service_role;

create or replace function public.cancel_own_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.release_checkout_reservation(p_order_id);
end;
$function$;

revoke all on function public.cancel_own_order(uuid) from public, anon, authenticated;
grant execute on function public.cancel_own_order(uuid) to authenticated;

create or replace function public.add_to_cart(
  p_product_id bigint,
  p_quantity integer default 1
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_stock integer;
  v_cart_id bigint;
  v_cart_quantity integer;
  v_reserved integer := 0;
begin
  if v_user is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 99 then
    raise exception 'INVALID_QUANTITY';
  end if;

  select p.stock into v_stock
  from public.products p
  where p.id = p_product_id
  for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  select ci.id, ci.quantity into v_cart_id, v_cart_quantity
  from public.cart_items ci
  where ci.user_id = v_user and ci.product_id = p_product_id
  for update;

  if found then
    select coalesce(sum(ri.quantity), 0)::integer into v_reserved
    from public.checkout_reservation_items ri
    join public.checkout_reservations r on r.order_id = ri.order_id
    where ri.cart_item_id = v_cart_id
      and ri.state = 'active'
      and r.state = 'active';
  else
    v_cart_quantity := 0;
  end if;

  if v_cart_quantity + p_quantity > 99 then
    raise exception 'INVALID_QUANTITY';
  end if;
  if v_cart_quantity + p_quantity - v_reserved > v_stock then
    raise exception 'OUT_OF_STOCK';
  end if;

  if v_cart_id is null then
    insert into public.cart_items (user_id, product_id, quantity)
    values (v_user, p_product_id, p_quantity);
  else
    update public.cart_items
    set quantity = v_cart_quantity + p_quantity
    where id = v_cart_id and user_id = v_user;
  end if;
end;
$function$;

create or replace function public.update_cart_quantity(
  p_cart_item_id bigint,
  p_quantity integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_product_id bigint;
  v_stock integer;
  v_cart_quantity integer;
  v_reserved integer;
begin
  if v_user is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 99 then
    raise exception 'INVALID_QUANTITY';
  end if;

  select ci.product_id into v_product_id
  from public.cart_items ci
  where ci.id = p_cart_item_id and ci.user_id = v_user;
  if not found then raise exception 'CART_ITEM_NOT_FOUND'; end if;

  select p.stock into v_stock
  from public.products p
  where p.id = v_product_id
  for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  select ci.quantity into v_cart_quantity
  from public.cart_items ci
  where ci.id = p_cart_item_id and ci.user_id = v_user
  for update;
  if not found then raise exception 'CART_ITEM_NOT_FOUND'; end if;

  select coalesce(sum(ri.quantity), 0)::integer into v_reserved
  from public.checkout_reservation_items ri
  join public.checkout_reservations r on r.order_id = ri.order_id
  where ri.cart_item_id = p_cart_item_id
    and ri.state = 'active'
    and r.state = 'active';

  if p_quantity < v_reserved then raise exception 'CART_QUANTITY_RESERVED'; end if;
  if p_quantity - v_reserved > v_stock then raise exception 'OUT_OF_STOCK'; end if;

  update public.cart_items ci
  set quantity = p_quantity
  where ci.id = p_cart_item_id and ci.user_id = v_user;
end;
$function$;

revoke all on function public.add_to_cart(bigint, integer)
  from public, anon, authenticated;
revoke all on function public.update_cart_quantity(bigint, integer)
  from public, anon, authenticated;
grant execute on function public.add_to_cart(bigint, integer) to authenticated;
grant execute on function public.update_cart_quantity(bigint, integer) to authenticated;

revoke all on function public.create_checkout_reservation_for_order()
  from public, anon, authenticated, service_role;
revoke all on function public.attach_checkout_reservation_item()
  from public, anon, authenticated, service_role;
revoke all on function public.preserve_reserved_cart_item()
  from public, anon, authenticated, service_role;
revoke all on function public.guard_reserved_cart_quantity()
  from public, anon, authenticated, service_role;
revoke all on function public.archive_offer_redemption_before_delete()
  from public, anon, authenticated, service_role;
revoke all on function public.sync_checkout_reservation_item_state()
  from public, anon, authenticated, service_role;
revoke all on function public.consume_checkout_reservation(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.consume_checkout_reservation_after_payment()
  from public, anon, authenticated, service_role;
revoke all on function public.guard_checkout_order_cancellation()
  from public, anon, authenticated, service_role;

commit;
