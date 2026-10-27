begin;

-- A historical attempt in state `created` with a provider order ID but no
-- dispatch timestamp is ambiguous. The timestamp was added later and its
-- absence cannot establish that payment was never dispatched or captured.
-- Keep such reservations held until a trusted server-side provider lookup
-- records authoritative noncapture through
-- record_authoritative_noncapture_and_release(). If that lookup is incomplete
-- or inconclusive, the order requires manual reconciliation and must remain
-- reserved.
do $preflight$
declare
  v_guard_oid oid := to_regprocedure(
    'public.guard_checkout_order_cancellation()'
  )::oid;
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.checkout_reservations') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regprocedure('public.release_checkout_reservation(uuid)') is null
     or to_regprocedure(
       'public.record_authoritative_noncapture_and_release(uuid,text,boolean,boolean,boolean,text)'
     ) is null
     or v_guard_oid is null then
    raise exception 'HISTORICAL_CREATED_RECOVERY_PREREQUISITES_MISSING';
  end if;

  if not exists (
       select 1
       from pg_catalog.pg_trigger t
       where t.tgrelid = to_regclass('public.orders')
         and t.tgname = 'orders_guard_checkout_cancellation'
         and t.tgfoid = v_guard_oid
         and t.tgenabled in ('O', 'A')
         and not t.tgisinternal
     )
     or (
       select count(*)
       from pg_catalog.pg_trigger t
       where t.tgrelid = to_regclass('public.orders')
         and t.tgfoid = v_guard_oid
         and not t.tgisinternal
     ) <> 1 then
    raise exception 'HISTORICAL_CREATED_RECOVERY_GUARD_BINDING_UNEXPECTED';
  end if;

  if exists (
    select 1
    from (values
      ('orders', 'id'),
      ('orders', 'status'),
      ('orders', 'payment_status'),
      ('orders', 'user_id'),
      ('orders', 'razorpay_order_id'),
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
    raise exception 'HISTORICAL_CREATED_RECOVERY_COLUMNS_MISSING';
  end if;

  -- The revised guard permits a null dispatch timestamp only after a
  -- noncapture transition has durable, order-matching evidence. Refuse to
  -- proceed if an existing noncaptured row does not meet that contract.
  if exists (
    select 1
    from public.razorpay_payment_attempts a
    join public.orders o on o.id = a.order_id
    where a.state = 'noncaptured'
      and (
        a.buyer_id is distinct from o.user_id
        or a.claim_token is not null
        or a.claim_lease_expires_at is not null
        or a.noncapture_verified_at is null
        or length(btrim(coalesce(a.noncapture_evidence_ref, ''))) not between 8 and 256
        or a.provider_order_id is null
        or a.provider_order_id is distinct from o.razorpay_order_id
        or a.provider_payment_id is not null
      )
  ) then
    raise exception 'HISTORICAL_NONCAPTURE_STATE_REQUIRES_RECONCILIATION';
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
          -- A historical `created` attempt may lack this later-added field.
          -- Only the service-only authoritative reconciliation RPC can turn
          -- that ambiguous attempt into `noncaptured`.
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

revoke all on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) to service_role;

comment on function public.guard_checkout_order_cancellation() is
  'Requires a released reservation. Missing dispatch timestamps are ambiguous; an attempt is releasable only after pre-dispatch proof or trusted, order-matching authoritative noncapture evidence.';
comment on function public.record_authoritative_noncapture_and_release(
  uuid, text, boolean, boolean, boolean, text
) is
  'Service-role-only recovery entry point. Its caller must complete an authoritative provider lookup, confirm no captured payment and a terminal provider order, and supply a durable evidence reference; inconclusive results must leave the reservation held.';

commit;
