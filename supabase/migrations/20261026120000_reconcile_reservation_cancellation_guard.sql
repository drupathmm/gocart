begin;

-- Replace the cancellation guard from 20261015120000 without rewriting that
-- historical migration. Reservation release may cancel an order only after
-- the database has a safe pre-dispatch or authoritative noncapture state.
do $preflight$
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.checkout_reservations') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regprocedure('public.guard_checkout_order_cancellation()') is null
     or to_regprocedure('public.release_checkout_reservation(uuid)') is null
     or not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = to_regclass('public.orders')
         and t.tgname = 'orders_guard_checkout_cancellation'
         and not t.tgisinternal
     ) then
    raise exception 'RESERVATION_CANCELLATION_GUARD_PREREQUISITES_MISSING';
  end if;

  if exists (
    select 1
    from (values
      ('checkout_reservations', 'order_id'),
      ('checkout_reservations', 'state'),
      ('razorpay_payment_attempts', 'order_id'),
      ('razorpay_payment_attempts', 'buyer_id'),
      ('razorpay_payment_attempts', 'state'),
      ('razorpay_payment_attempts', 'dispatch_started_at'),
      ('razorpay_payment_attempts', 'claim_lease_expires_at'),
      ('razorpay_payment_attempts', 'claim_token'),
      ('razorpay_payment_attempts', 'provider_order_id'),
      ('razorpay_payment_attempts', 'provider_payment_id'),
      ('razorpay_payment_attempts', 'noncapture_verified_at'),
      ('razorpay_payment_attempts', 'noncapture_evidence_ref')
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
    raise exception 'RESERVATION_CANCELLATION_GUARD_COLUMNS_MISSING';
  end if;
end;
$preflight$;

create or replace function public.guard_checkout_order_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation_state text;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_safe_noncapture boolean;
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
      v_safe_noncapture :=
        (
          v_attempt.state = 'abandoned_before_dispatch'
          and v_attempt.dispatch_started_at is null
          and v_attempt.claim_token is null
          and v_attempt.claim_lease_expires_at is null
          and v_attempt.provider_order_id is null
          and v_attempt.provider_payment_id is null
          and v_attempt.noncapture_verified_at is null
          and v_attempt.noncapture_evidence_ref is null
        )
        or (
          v_attempt.state = 'noncaptured'
          and v_attempt.dispatch_started_at is not null
          and v_attempt.claim_token is null
          and v_attempt.claim_lease_expires_at is null
          and v_attempt.noncapture_verified_at is not null
          and length(btrim(coalesce(v_attempt.noncapture_evidence_ref, ''))) between 8 and 256
          and v_attempt.provider_order_id is not null
          and v_attempt.provider_order_id is not distinct from new.razorpay_order_id
          and v_attempt.provider_payment_id is null
        );

      if v_attempt.buyer_id is distinct from new.user_id
         or v_safe_noncapture is distinct from true then
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
  'Requires a released reservation and accepts payment attempts only when abandoned before dispatch or authoritatively recorded as noncaptured.';

commit;
