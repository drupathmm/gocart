begin;

do $preflight$
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.checkout_reservations') is null
     or to_regclass('public.checkout_reservation_items') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regclass('public.products') is null
     or to_regclass('public.offer_redemptions') is null
     or to_regclass('public.offers') is null
     or to_regprocedure('public.release_checkout_reservation(uuid)') is null
     or to_regprocedure('public.guard_checkout_order_cancellation()') is null
     or to_regprocedure(
       'public.record_authoritative_noncapture_and_release(uuid,text,boolean,boolean,boolean,text)'
     ) is null
     or not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = to_regclass('public.orders')
         and t.tgname = 'orders_guard_checkout_cancellation'
         and t.tgfoid = to_regprocedure('public.guard_checkout_order_cancellation()')::oid
         and t.tgenabled in ('O', 'A')
         and not t.tgisinternal
     )
     or (
       select count(*)
       from pg_catalog.pg_trigger t
       where t.tgrelid = to_regclass('public.orders')
         and t.tgfoid = to_regprocedure('public.guard_checkout_order_cancellation()')::oid
         and not t.tgisinternal
     ) <> 1 then
    raise exception 'NONCAPTURE_RECOVERY_PREREQUISITES_MISSING';
  end if;

  if exists (
    select 1
    from (values
      ('orders', 'id'), ('orders', 'user_id'), ('orders', 'status'),
      ('orders', 'payment_status'), ('orders', 'razorpay_order_id'),
      ('checkout_reservations', 'order_id'), ('checkout_reservations', 'state'),
      ('checkout_reservations', 'source'), ('checkout_reservations', 'expires_at'),
      ('checkout_reservations', 'released_at'), ('checkout_reservations', 'released_by'),
      ('checkout_reservations', 'release_reason'),
      ('checkout_reservation_items', 'order_id'),
      ('checkout_reservation_items', 'state'),
      ('checkout_reservation_items', 'product_id'),
      ('checkout_reservation_items', 'quantity'),
      ('razorpay_payment_attempts', 'order_id'),
      ('razorpay_payment_attempts', 'state'),
      ('razorpay_payment_attempts', 'dispatch_started_at'),
      ('razorpay_payment_attempts', 'claim_lease_expires_at'),
      ('razorpay_payment_attempts', 'claim_token'),
      ('razorpay_payment_attempts', 'provider_order_id'),
      ('razorpay_payment_attempts', 'provider_payment_id'),
      ('razorpay_payment_attempts', 'buyer_id'),
      ('razorpay_payment_attempts', 'noncapture_verified_at'),
      ('razorpay_payment_attempts', 'noncapture_evidence_ref'),
      ('products', 'id'), ('products', 'stock'), ('products', 'updated_at'),
      ('offer_redemptions', 'order_id'), ('offer_redemptions', 'offer_id'),
      ('offers', 'id'), ('offers', 'used_count')
    ) as required(table_name, column_name)
    where not exists (
      select 1
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass('public.' || required.table_name)
        and a.attname = required.column_name
        and a.attnum > 0
        and not a.attisdropped
    )
  ) then
    raise exception 'NONCAPTURE_RECOVERY_COLUMNS_MISSING';
  end if;
end;
$preflight$;

-- Keep the order trigger aligned with this release contract: only a proven
-- pre-dispatch abandonment may accompany a released reservation. Mutable
-- noncapture timestamps and references no longer authorize cancellation.
create or replace function public.guard_checkout_order_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation_state text;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_safe_predispatch boolean;
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
    where r.order_id = new.id
    for update;
    if v_reservation_state is distinct from 'released' then
      raise exception 'CHECKOUT_RESERVATION_RELEASE_REQUIRED';
    end if;

    select * into v_attempt
    from public.razorpay_payment_attempts a
    where a.order_id = new.id
    for update;

    if found then
      v_safe_predispatch :=
        v_attempt.state = 'abandoned_before_dispatch'
        and v_attempt.dispatch_started_at is null
        and v_attempt.claim_token is null
        and v_attempt.claim_lease_expires_at is null
        and v_attempt.provider_order_id is null
        and v_attempt.provider_payment_id is null
        and v_attempt.noncapture_verified_at is null
        and v_attempt.noncapture_evidence_ref is null;

      if v_attempt.buyer_id is distinct from new.user_id
         or v_safe_predispatch is distinct from true then
        raise exception 'PAYMENT_RECONCILIATION_REQUIRED';
      end if;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.guard_checkout_order_cancellation()
  from public, anon, authenticated, service_role;

comment on function public.guard_checkout_order_cancellation() is
  'Requires a released reservation. Cancellation with a payment attempt is allowed only for a proven pre-dispatch abandonment; local noncapture flags and references are insufficient.';

-- Keep safe pre-dispatch and no-attempt recovery atomic, but do not trust local
-- noncapture flags or references as a basis for releasing inventory.
create or replace function public.release_checkout_reservation(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_reservation public.checkout_reservations%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_has_attempt boolean := false;
  v_offer_id uuid;
  v_offer_used_count integer;
  v_line record;
  v_role text := coalesce(auth.role(), '');
  v_user_id uuid := auth.uid();
begin
  select * into v_order from public.orders o
  where o.id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_role <> 'service_role'
     and (v_user_id is null or v_user_id <> v_order.user_id) then
    raise exception 'NOT_AUTHORIZED';
  end if;

  select * into v_reservation from public.checkout_reservations r
  where r.order_id = p_order_id for update;
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_FOUND'; end if;
  if v_reservation.state = 'released' and v_order.status = 'cancelled' then return false; end if;
  if v_reservation.state = 'consumed' or v_order.status = 'paid'
     or v_order.payment_status = 'paid' then
    raise exception 'PAYMENT_ALREADY_CAPTURED';
  end if;
  if v_reservation.state <> 'active' or v_order.status <> 'pending'
     or v_order.payment_status <> 'unpaid' then
    raise exception 'CHECKOUT_RESERVATION_NOT_RELEASABLE';
  end if;
  if v_reservation.source = 'legacy' then
    raise exception 'LEGACY_CHECKOUT_REQUIRES_RECONCILIATION';
  end if;

  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id for update;
  v_has_attempt := found;
  if v_has_attempt then
    if v_attempt.state = 'creating'
       and v_attempt.dispatch_started_at is null
       and v_attempt.claim_lease_expires_at is not null
       and v_attempt.claim_lease_expires_at <= clock_timestamp() then
      update public.razorpay_payment_attempts a
      set state = 'abandoned_before_dispatch', claim_token = null,
          claim_lease_expires_at = null, updated_at = clock_timestamp()
      where a.id = v_attempt.id;
      v_attempt.state := 'abandoned_before_dispatch';
    end if;

    if not (v_attempt.state = 'abandoned_before_dispatch'
        and v_attempt.dispatch_started_at is null
        and v_attempt.claim_token is null
        and v_attempt.claim_lease_expires_at is null
        and v_attempt.provider_order_id is null
        and v_attempt.provider_payment_id is null
        and v_attempt.noncapture_verified_at is null
        and v_attempt.noncapture_evidence_ref is null) then
      raise exception 'PAYMENT_RECONCILIATION_REQUIRED';
    end if;
  end if;

  if not exists (
    select 1 from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
  ) then raise exception 'CHECKOUT_RESERVATION_ITEMS_MISSING'; end if;

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
  set stock = p.stock + reserved.quantity, updated_at = clock_timestamp()
  from (
    select ri.product_id, sum(ri.quantity)::integer as quantity
    from public.checkout_reservation_items ri
    where ri.order_id = p_order_id and ri.state = 'active'
    group by ri.product_id
  ) reserved
  where p.id = reserved.product_id;

  select r.offer_id into v_offer_id
  from public.offer_redemptions r where r.order_id = p_order_id for update;
  if found then
    select o.used_count into v_offer_used_count
    from public.offers o where o.id = v_offer_id for update;
    if not found or v_offer_used_count < 1 then
      raise exception 'OFFER_RESERVATION_INVARIANT_FAILED';
    end if;
    update public.offers set used_count = used_count - 1 where id = v_offer_id;
    perform pg_catalog.set_config(
      'gocart.offer_redemption_archive_reason', 'checkout_reservation_released', true
    );
    delete from public.offer_redemptions where order_id = p_order_id;
  end if;

  update public.checkout_reservations
  set state = 'released', released_at = clock_timestamp(), released_by = v_user_id,
      release_reason = case
        when v_role = 'service_role' and v_reservation.expires_at <= clock_timestamp()
          and v_has_attempt then 'checkout_reservation_expired_before_dispatch'
        when v_role = 'service_role' and v_reservation.expires_at <= clock_timestamp()
          then 'checkout_reservation_expired_without_payment_attempt'
        when v_role = 'service_role' then 'service_release_without_payment_attempt'
        else 'buyer_cancelled_without_payment_attempt'
      end
  where order_id = p_order_id and state = 'active';
  if not found then raise exception 'CHECKOUT_RESERVATION_NOT_ACTIVE'; end if;

  update public.orders set status = 'cancelled', payment_status = 'cancelled'
  where id = p_order_id;
  return true;
end;
$function$;

revoke all on function public.release_checkout_reservation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.release_checkout_reservation(uuid)
  to authenticated, service_role;

-- The supported Orders API response exposes current order/payment states, but
-- this project has no verified provider-terminal-noncapture contract. Keep the
-- legacy boolean/reference RPC as an explicit fail-closed stub so an accidental
-- future grant cannot turn caller assertions into released stock or offers.
create or replace function public.record_authoritative_noncapture_and_release(
  p_order_id uuid,
  p_provider_order_id text,
  p_lookup_complete boolean,
  p_no_captured_payment boolean,
  p_provider_order_terminal boolean,
  p_evidence_reference text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  raise exception 'AUTOMATIC_NONCAPTURE_UNSUPPORTED';
end;
$function$;

revoke all on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) from public, anon, authenticated, service_role;

comment on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) is
  'Disabled fail-closed. Caller booleans and evidence references are not proof of provider noncapture. Reservations remain held for manual reconciliation until a verified provider-terminal state and durable digest-bound audit contract exist.';

comment on function public.release_checkout_reservation(uuid) is
  'Atomically restores stock and offer capacity only for orders with no payment attempt or a proven pre-dispatch abandoned attempt. Provider noncapture is not an automatic release condition.';

commit;
