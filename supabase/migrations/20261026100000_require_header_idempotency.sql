begin;

-- Request keys and successful response payloads are kept behind definer RPCs.
-- The table has no client policies or direct grants.
create table public.idempotency_keys (
  idempotency_key text primary key
    check (length(btrim(idempotency_key)) between 8 and 128),
  user_id uuid not null references public.profiles (id) on delete cascade,
  operation text not null
    check (operation in ('checkout', 'razorpay_order', 'payment_verification')),
  resource_id uuid references public.orders (id) on delete restrict,
  response_payload jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  claim_token uuid,
  lease_expires_at timestamptz,
  check (
    (response_payload is null and completed_at is null
      and ((claim_token is null and lease_expires_at is null)
        or (claim_token is not null and lease_expires_at is not null)))
    or (response_payload is not null and completed_at is not null
      and claim_token is null and lease_expires_at is null)
  )
);

create index idempotency_keys_user_created_idx
  on public.idempotency_keys (user_id, created_at desc);
create index idempotency_keys_resource_idx
  on public.idempotency_keys (resource_id)
  where resource_id is not null;
create index idempotency_keys_verification_lease_idx
  on public.idempotency_keys (lease_expires_at)
  where operation = 'payment_verification' and response_payload is null;

alter table public.idempotency_keys enable row level security;
revoke all on public.idempotency_keys
  from public, anon, authenticated, service_role;

create or replace function public.checkout_place_order_cached(
  p_offer_code text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_existing public.idempotency_keys%rowtype;
  v_inserted integer;
  v_order_id uuid;
  v_payload jsonb;
begin
  if v_user is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  -- Serialize equal keys across both checkout and payment operations.
  perform pg_advisory_xact_lock(hashtext('gocart-idempotency:' || v_key));
  insert into public.idempotency_keys (
    idempotency_key, user_id, operation
  ) values (v_key, v_user, 'checkout')
  on conflict (idempotency_key) do nothing;
  get diagnostics v_inserted = row_count;

  select * into v_existing
  from public.idempotency_keys k
  where k.idempotency_key = v_key
  for update;

  if v_existing.user_id <> v_user or v_existing.operation <> 'checkout' then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;
  if v_inserted = 0 then
    if v_existing.response_payload is null then
      raise exception 'IDEMPOTENCY_IN_PROGRESS';
    end if;
    return v_existing.response_payload;
  end if;

  v_order_id := public.place_order(p_offer_code, v_key);
  select jsonb_build_object(
    'order_id', o.id,
    'total_amount', o.total_amount,
    'payment_status', o.payment_status
  ) into v_payload
  from public.orders o
  where o.id = v_order_id and o.user_id = v_user;
  if v_payload is null then raise exception 'CHECKOUT_FAILED'; end if;

  update public.idempotency_keys
  set resource_id = v_order_id,
      response_payload = v_payload,
      completed_at = clock_timestamp()
  where idempotency_key = v_key and user_id = v_user;
  return v_payload;
end;
$function$;

-- Keep the old authenticated RPC signature working while routing it through
-- the same durable response cache.
create or replace function public.checkout_place_order(
  p_offer_code text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  v_payload := public.checkout_place_order_cached(p_offer_code, p_idempotency_key);
  return (v_payload ->> 'order_id')::uuid;
end;
$function$;

revoke all on function public.checkout_place_order_cached(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.checkout_place_order_cached(text, text)
  to authenticated;
revoke all on function public.checkout_place_order(text, text)
  from public, anon, authenticated;
grant execute on function public.checkout_place_order(text, text)
  to authenticated;

-- Bind Razorpay order creation to a request key as well. A stable key is
-- assigned to each GoCart order; provider order recovery remains in the
-- existing payment attempt state machine.
alter table public.razorpay_payment_attempts
  add column create_idempotency_key text,
  add constraint razorpay_attempt_create_key_length_check
    check (
      create_idempotency_key is null
      or length(btrim(create_idempotency_key)) between 8 and 128
    );
create unique index razorpay_attempt_create_key_uidx
  on public.razorpay_payment_attempts (create_idempotency_key)
  where create_idempotency_key is not null;

create or replace function public.claim_razorpay_order_with_key(
  p_order_id uuid,
  p_buyer_id uuid,
  p_idempotency_key text
)
returns table (
  claim_state text,
  claim_token uuid,
  provider_order_id text,
  amount_paise bigint,
  currency text,
  response_payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_key_row public.idempotency_keys%rowtype;
  v_claim record;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  insert into public.idempotency_keys (
    idempotency_key, user_id, operation, resource_id
  ) values (v_key, p_buyer_id, 'razorpay_order', p_order_id)
  on conflict (idempotency_key) do nothing;
  select * into v_key_row
  from public.idempotency_keys k
  where k.idempotency_key = v_key
  for update;

  if v_key_row.user_id <> p_buyer_id
     or v_key_row.operation <> 'razorpay_order'
     or v_key_row.resource_id is distinct from p_order_id then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;
  if v_key_row.response_payload is not null then
    return query select
      'cached'::text,
      null::uuid,
      v_key_row.response_payload ->> 'razorpay_order_id',
      (v_key_row.response_payload ->> 'amount')::bigint,
      v_key_row.response_payload ->> 'currency',
      v_key_row.response_payload;
    return;
  end if;

  select c.* into v_claim
  from public.claim_razorpay_order(p_order_id, p_buyer_id) c;
  if not found then raise exception 'PAYMENT_ORDER_CLAIM_FAILED'; end if;

  begin
    update public.razorpay_payment_attempts a
    set create_idempotency_key = v_key
    where a.order_id = p_order_id
      and a.create_idempotency_key is null;
  exception when unique_violation then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end;

  if not exists (
    select 1 from public.razorpay_payment_attempts a
    where a.order_id = p_order_id and a.create_idempotency_key = v_key
  ) then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;

  return query select
    v_claim.claim_state::text,
    v_claim.claim_token::uuid,
    v_claim.provider_order_id::text,
    v_claim.amount_paise::bigint,
    v_claim.currency::text,
    null::jsonb;
end;
$function$;

create or replace function public.cache_razorpay_order_response(
  p_order_id uuid,
  p_idempotency_key text,
  p_response_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_payload jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128
     or jsonb_typeof(p_response_payload) <> 'object'
     or p_response_payload ->> 'order_id' is distinct from p_order_id::text
     or coalesce(p_response_payload ->> 'razorpay_order_id', '') = '' then
    raise exception 'INVALID_PAYMENT_RESPONSE';
  end if;

  select k.response_payload into v_payload
  from public.idempotency_keys k
  where k.idempotency_key = v_key
    and k.operation = 'razorpay_order'
    and k.resource_id = p_order_id
  for update;
  if not found then raise exception 'IDEMPOTENCY_KEY_NOT_FOUND'; end if;

  if v_payload is null then
    update public.idempotency_keys k
    set response_payload = p_response_payload,
        completed_at = clock_timestamp()
    where k.idempotency_key = v_key
      and k.operation = 'razorpay_order'
      and k.resource_id = p_order_id
    returning k.response_payload into v_payload;
  end if;
  return v_payload;
end;
$function$;

create or replace function public.complete_razorpay_order_cached(
  p_order_id uuid,
  p_claim_token uuid,
  p_provider_order_id text,
  p_idempotency_key text,
  p_response_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_response_payload ->> 'razorpay_order_id' is distinct from p_provider_order_id then
    raise exception 'INVALID_PAYMENT_RESPONSE';
  end if;

  perform public.complete_razorpay_order(
    p_order_id, p_claim_token, p_provider_order_id
  );
  v_payload := public.cache_razorpay_order_response(
    p_order_id, p_idempotency_key, p_response_payload
  );
  return v_payload;
end;
$function$;

-- Payment verification also receives retries from mobile clients. A short
-- lease fences simultaneous attempts; successful responses are cached and
-- returned to subsequent requests using the same key.
create or replace function public.claim_payment_verification(
  p_user_id uuid,
  p_order_id uuid,
  p_idempotency_key text
)
returns table (
  claim_state text,
  claim_token uuid,
  response_payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_key_row public.idempotency_keys%rowtype;
  v_token uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_IDEMPOTENCY_KEY';
  end if;

  insert into public.idempotency_keys (
    idempotency_key, user_id, operation, resource_id,
    claim_token, lease_expires_at
  ) values (
    v_key, p_user_id, 'payment_verification', p_order_id,
    gen_random_uuid(), clock_timestamp() + interval '30 seconds'
  ) on conflict (idempotency_key) do nothing;

  select * into v_key_row
  from public.idempotency_keys k
  where k.idempotency_key = v_key
  for update;
  if v_key_row.user_id <> p_user_id
     or v_key_row.operation <> 'payment_verification'
     or v_key_row.resource_id is distinct from p_order_id then
    raise exception 'IDEMPOTENCY_CONFLICT';
  end if;
  if v_key_row.response_payload is not null then
    return query select 'cached'::text, null::uuid, v_key_row.response_payload;
    return;
  end if;
  if v_key_row.claim_token is not null
     and v_key_row.lease_expires_at > clock_timestamp() then
    return query select 'in_progress'::text, null::uuid, null::jsonb;
    return;
  end if;

  v_token := gen_random_uuid();
  update public.idempotency_keys k
  set claim_token = v_token,
      lease_expires_at = clock_timestamp() + interval '30 seconds'
  where k.idempotency_key = v_key;
  return query select 'claimed'::text, v_token, null::jsonb;
end;
$function$;

create or replace function public.cache_payment_verification_response(
  p_user_id uuid,
  p_order_id uuid,
  p_idempotency_key text,
  p_claim_token uuid,
  p_response_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_key_row public.idempotency_keys%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if jsonb_typeof(p_response_payload) <> 'object'
     or p_response_payload ->> 'order_id' is distinct from p_order_id::text then
    raise exception 'INVALID_PAYMENT_RESPONSE';
  end if;

  select * into v_key_row
  from public.idempotency_keys k
  where k.idempotency_key = v_key
    and k.user_id = p_user_id
    and k.operation = 'payment_verification'
    and k.resource_id = p_order_id
  for update;
  if not found then raise exception 'IDEMPOTENCY_KEY_NOT_FOUND'; end if;
  if v_key_row.response_payload is not null then
    return v_key_row.response_payload;
  end if;
  if v_key_row.claim_token is distinct from p_claim_token
     or v_key_row.lease_expires_at <= clock_timestamp() then
    raise exception 'IDEMPOTENCY_CLAIM_CONFLICT';
  end if;

  update public.idempotency_keys k
  set response_payload = p_response_payload,
      completed_at = clock_timestamp(),
      claim_token = null,
      lease_expires_at = null
  where k.idempotency_key = v_key
  returning k.* into v_key_row;
  return v_key_row.response_payload;
end;
$function$;

create or replace function public.release_payment_verification_claim(
  p_idempotency_key text,
  p_claim_token uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  update public.idempotency_keys k
  set claim_token = null,
      lease_expires_at = null
  where k.idempotency_key = p_idempotency_key
    and k.operation = 'payment_verification'
    and k.response_payload is null
    and k.claim_token = p_claim_token;
end;
$function$;

revoke all on function public.claim_razorpay_order(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.complete_razorpay_order(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.claim_razorpay_order_with_key(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.cache_razorpay_order_response(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_razorpay_order_cached(uuid, uuid, text, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_payment_verification(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.cache_payment_verification_response(uuid, uuid, text, uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.release_payment_verification_claim(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_razorpay_order_with_key(uuid, uuid, text)
  to service_role;
grant execute on function public.claim_razorpay_order(uuid, uuid)
  to service_role;
grant execute on function public.complete_razorpay_order(uuid, uuid, text)
  to service_role;
grant execute on function public.cache_razorpay_order_response(uuid, text, jsonb)
  to service_role;
grant execute on function public.complete_razorpay_order_cached(uuid, uuid, text, text, jsonb)
  to service_role;
grant execute on function public.claim_payment_verification(uuid, uuid, text)
  to service_role;
grant execute on function public.cache_payment_verification_response(uuid, uuid, text, uuid, jsonb)
  to service_role;
grant execute on function public.release_payment_verification_claim(text, uuid)
  to service_role;

commit;
