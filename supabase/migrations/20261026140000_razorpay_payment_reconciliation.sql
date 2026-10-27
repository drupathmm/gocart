begin;

do $preflight$
begin
  if to_regclass('public.orders') is null
     or to_regclass('public.razorpay_payment_attempts') is null
     or to_regprocedure(
       'public.record_verified_razorpay_payment(uuid,uuid,text,text,bigint,text)'
     ) is null then
    raise exception 'RAZORPAY_RECONCILIATION_PREREQUISITES_MISSING';
  end if;

  if exists (
    select 1
    from (values
      ('orders', 'id'),
      ('orders', 'user_id'),
      ('orders', 'status'),
      ('orders', 'payment_status'),
      ('orders', 'razorpay_order_id'),
      ('razorpay_payment_attempts', 'id'),
      ('razorpay_payment_attempts', 'order_id'),
      ('razorpay_payment_attempts', 'buyer_id'),
      ('razorpay_payment_attempts', 'provider_order_id'),
      ('razorpay_payment_attempts', 'provider_payment_id'),
      ('razorpay_payment_attempts', 'expected_amount_paise'),
      ('razorpay_payment_attempts', 'currency'),
      ('razorpay_payment_attempts', 'state')
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
    raise exception 'RAZORPAY_RECONCILIATION_COLUMNS_MISSING';
  end if;
end;
$preflight$;

-- This ledger records server-side provider observations and idempotent
-- reconciliation responses. It intentionally does not store raw provider
-- payloads or customer payment details.
create table public.razorpay_payment_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  attempt_id uuid references public.razorpay_payment_attempts(id) on delete restrict,
  local_order_status text,
  local_payment_status text,
  local_attempt_state text,
  existing_provider_payment_id text,
  expected_amount_paise bigint check (
    expected_amount_paise is null or expected_amount_paise > 0
  ),
  currency text check (currency is null or currency = 'INR'),
  idempotency_key text not null unique
    check (length(btrim(idempotency_key)) between 8 and 128),
  claim_token uuid,
  lease_expires_at timestamptz,
  decision text not null check (decision in (
    'processing', 'captured', 'review_required', 'noncapture_unconfirmed',
    'provider_error', 'attempt_unavailable'
  )),
  provider_order_id text,
  provider_order_status text check (
    provider_order_status is null or provider_order_status in (
      'created', 'attempted', 'paid', 'unknown'
    )
  ),
  provider_attempt_count integer check (
    provider_attempt_count is null or provider_attempt_count >= 0
  ),
  provider_payment_count integer check (
    provider_payment_count is null or provider_payment_count >= 0
  ),
  evidence_sha256 text check (
    evidence_sha256 is null or evidence_sha256 ~ '^[a-f0-9]{64}$'
  ),
  evidence_summary jsonb check (
    evidence_summary is null or (
      jsonb_typeof(evidence_summary) = 'object'
      and pg_catalog.pg_column_size(evidence_summary) <= 65536
    )
  ),
  error_code text check (
    error_code is null or (length(error_code) between 1 and 80
      and error_code ~ '^[A-Z0-9_]+$')
  ),
  response_http_status integer check (
    response_http_status is null or response_http_status between 200 and 599
  ),
  response_payload jsonb,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (
    (decision = 'processing'
      and claim_token is not null and lease_expires_at is not null
      and response_http_status is null and response_payload is null
      and completed_at is null)
    or (decision <> 'processing'
      and claim_token is null and lease_expires_at is null
      and response_http_status is not null
      and response_payload is not null
      and jsonb_typeof(response_payload) = 'object'
      and completed_at is not null)
  )
);

create index razorpay_reconciliation_order_created_idx
  on public.razorpay_payment_reconciliation_runs (order_id, created_at desc);
create index razorpay_reconciliation_active_lease_idx
  on public.razorpay_payment_reconciliation_runs (lease_expires_at)
  where decision = 'processing';

alter table public.razorpay_payment_reconciliation_runs enable row level security;
revoke all on public.razorpay_payment_reconciliation_runs
  from public, anon, authenticated, service_role;

create or replace function public.claim_razorpay_payment_reconciliation(
  p_order_id uuid,
  p_idempotency_key text
)
returns table (
  claim_state text,
  run_id uuid,
  claim_token uuid,
  attempt_id uuid,
  provider_order_id text,
  expected_amount_paise bigint,
  currency text,
  order_status text,
  payment_status text,
  cached_response jsonb,
  cached_http_status integer,
  attempt_state text,
  existing_provider_payment_id text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_run public.razorpay_payment_reconciliation_runs%rowtype;
  v_order public.orders%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_token uuid;
  v_inserted integer := 0;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_order_id is null or v_key is null or length(v_key) < 8 or length(v_key) > 128 then
    raise exception 'INVALID_RECONCILIATION_REQUEST';
  end if;
  if not exists (select 1 from public.orders o where o.id = p_order_id) then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gocart-reconciliation:' || v_key, 0)
  );

  v_token := gen_random_uuid();
  insert into public.razorpay_payment_reconciliation_runs (
    order_id, idempotency_key, claim_token, lease_expires_at, decision
  ) values (
    p_order_id, v_key, v_token, clock_timestamp() + interval '2 minutes', 'processing'
  ) on conflict (idempotency_key) do nothing;
  get diagnostics v_inserted = row_count;

  select * into v_run
  from public.razorpay_payment_reconciliation_runs r
  where r.idempotency_key = v_key
  for update;

  if v_run.order_id is distinct from p_order_id then
    return query select 'conflict'::text, v_run.id, null::uuid, v_run.attempt_id,
      null::text, null::bigint, null::text, null::text, null::text, null::jsonb, null::integer,
      null::text, null::text;
    return;
  end if;
  if v_run.decision <> 'processing' then
    return query select 'cached'::text, v_run.id, null::uuid, v_run.attempt_id,
      v_run.provider_order_id, null::bigint, null::text, null::text, null::text,
      v_run.response_payload, v_run.response_http_status, v_run.local_attempt_state,
      v_run.existing_provider_payment_id;
    return;
  end if;
  if v_inserted = 0 and v_run.lease_expires_at > clock_timestamp() then
    return query select 'in_progress'::text, v_run.id, null::uuid, v_run.attempt_id,
      v_run.provider_order_id, null::bigint, null::text, null::text, null::text,
      null::jsonb, null::integer, null::text, null::text;
    return;
  end if;

  if v_inserted = 0 then
    v_token := gen_random_uuid();
    update public.razorpay_payment_reconciliation_runs r
    set claim_token = v_token,
        lease_expires_at = clock_timestamp() + interval '2 minutes',
        updated_at = clock_timestamp()
    where r.id = v_run.id
    returning * into v_run;
  else
    v_token := v_run.claim_token;
  end if;

  select * into v_order from public.orders o where o.id = p_order_id;
  select * into v_attempt from public.razorpay_payment_attempts a
  where a.order_id = p_order_id;
  update public.razorpay_payment_reconciliation_runs r
  set attempt_id = v_attempt.id,
      provider_order_id = v_attempt.provider_order_id,
      local_order_status = v_order.status,
      local_payment_status = v_order.payment_status,
      local_attempt_state = v_attempt.state,
      existing_provider_payment_id = v_attempt.provider_payment_id,
      expected_amount_paise = v_attempt.expected_amount_paise,
      currency = v_attempt.currency,
      updated_at = clock_timestamp()
  where r.id = v_run.id
  returning * into v_run;

  return query select 'claimed'::text, v_run.id, v_token, v_attempt.id,
    v_attempt.provider_order_id, v_attempt.expected_amount_paise, v_attempt.currency,
    v_order.status, v_order.payment_status, null::jsonb, null::integer,
    v_attempt.state, v_attempt.provider_payment_id;
end;
$function$;

create or replace function public.finish_razorpay_payment_reconciliation(
  p_run_id uuid,
  p_claim_token uuid,
  p_decision text,
  p_provider_order_status text,
  p_provider_attempt_count integer,
  p_provider_payment_count integer,
  p_evidence_sha256 text,
  p_evidence_summary jsonb,
  p_error_code text,
  p_response_http_status integer,
  p_response_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.razorpay_payment_reconciliation_runs%rowtype;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_decision is null or p_decision not in (
       'review_required', 'noncapture_unconfirmed', 'provider_error', 'attempt_unavailable'
     )
     or p_provider_order_status is not null
       and p_provider_order_status not in ('created', 'attempted', 'paid', 'unknown')
     or p_provider_attempt_count is not null and p_provider_attempt_count < 0
     or p_provider_payment_count is not null and p_provider_payment_count < 0
     or p_evidence_sha256 is not null and p_evidence_sha256 !~ '^[a-f0-9]{64}$'
     or p_evidence_summary is not null
       and (jsonb_typeof(p_evidence_summary) <> 'object'
         or pg_catalog.pg_column_size(p_evidence_summary) > 65536)
     or p_error_code is not null
       and (length(p_error_code) not between 1 and 80 or p_error_code !~ '^[A-Z0-9_]+$')
     or p_response_http_status is null or p_response_http_status not between 200 and 599
     or p_response_payload is null or jsonb_typeof(p_response_payload) <> 'object'
     or p_response_payload ->> 'order_id' is distinct from (
       select r.order_id::text from public.razorpay_payment_reconciliation_runs r
       where r.id = p_run_id
     ) then
    raise exception 'INVALID_RECONCILIATION_RESULT';
  end if;

  select * into v_run from public.razorpay_payment_reconciliation_runs r
  where r.id = p_run_id for update;
  if not found or v_run.decision <> 'processing'
     or v_run.claim_token is distinct from p_claim_token
     or v_run.lease_expires_at <= clock_timestamp() then
    raise exception 'RECONCILIATION_CLAIM_CONFLICT';
  end if;

  update public.razorpay_payment_reconciliation_runs r
  set decision = p_decision,
      provider_order_status = p_provider_order_status,
      provider_attempt_count = p_provider_attempt_count,
      provider_payment_count = p_provider_payment_count,
      evidence_sha256 = p_evidence_sha256,
      evidence_summary = p_evidence_summary,
      error_code = p_error_code,
      response_http_status = p_response_http_status,
      response_payload = p_response_payload,
      completed_at = clock_timestamp(),
      claim_token = null,
      lease_expires_at = null,
      updated_at = clock_timestamp()
  where r.id = v_run.id;
  return jsonb_build_object(
    'response_payload', p_response_payload,
    'http_status', p_response_http_status
  );
end;
$function$;

create or replace function public.record_reconciled_razorpay_capture(
  p_run_id uuid,
  p_claim_token uuid,
  p_provider_payment_id text,
  p_amount_paise bigint,
  p_currency text,
  p_provider_attempt_count integer,
  p_provider_payment_count integer,
  p_evidence_sha256 text,
  p_evidence_summary jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.razorpay_payment_reconciliation_runs%rowtype;
  v_attempt public.razorpay_payment_attempts%rowtype;
  v_order public.orders%rowtype;
  v_result text;
  v_decision text;
  v_payload jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_run_id is null or p_claim_token is null
     or p_provider_payment_id is null or length(btrim(p_provider_payment_id)) = 0
     or p_amount_paise is null or p_amount_paise <= 0
     or p_currency is distinct from 'INR'
     or p_provider_attempt_count is null or p_provider_attempt_count < 0
     or p_provider_payment_count is null or p_provider_payment_count < 0
     or p_evidence_sha256 is null or p_evidence_sha256 !~ '^[a-f0-9]{64}$'
     or p_evidence_summary is null
     or jsonb_typeof(p_evidence_summary) <> 'object'
     or pg_catalog.pg_column_size(p_evidence_summary) > 65536 then
    raise exception 'INVALID_CAPTURE_RECONCILIATION';
  end if;

  select * into v_run from public.razorpay_payment_reconciliation_runs r
  where r.id = p_run_id for update;
  if not found or v_run.decision <> 'processing'
     or v_run.claim_token is distinct from p_claim_token
     or v_run.lease_expires_at <= clock_timestamp() then
    raise exception 'RECONCILIATION_CLAIM_CONFLICT';
  end if;
  if v_run.attempt_id is null or v_run.provider_order_id is null then
    raise exception 'PAYMENT_ATTEMPT_NOT_FOUND';
  end if;

  select * into v_attempt from public.razorpay_payment_attempts a
  where a.id = v_run.attempt_id;
  if not found or v_attempt.provider_order_id is distinct from v_run.provider_order_id then
    raise exception 'PROVIDER_ORDER_MISMATCH';
  end if;

  v_result := public.record_verified_razorpay_payment(
    v_attempt.order_id,
    v_attempt.buyer_id,
    v_attempt.provider_order_id,
    p_provider_payment_id,
    p_amount_paise,
    p_currency
  );
  select * into v_order from public.orders o where o.id = v_attempt.order_id;
  v_decision := case when v_result = 'review_required' then 'review_required' else 'captured' end;
  v_payload := jsonb_build_object(
    'order_id', v_order.id,
    'status', v_order.status,
    'payment_status', v_order.payment_status,
    'reconciliation_result', v_result,
    'reservation_action', 'none'
  );

  update public.razorpay_payment_reconciliation_runs r
  set decision = v_decision,
      provider_order_status = 'paid',
      provider_attempt_count = p_provider_attempt_count,
      provider_payment_count = p_provider_payment_count,
      evidence_sha256 = p_evidence_sha256,
      evidence_summary = p_evidence_summary,
      response_http_status = 200,
      response_payload = v_payload,
      completed_at = clock_timestamp(),
      claim_token = null,
      lease_expires_at = null,
      updated_at = clock_timestamp()
  where r.id = v_run.id;
  return jsonb_build_object('response_payload', v_payload, 'http_status', 200);
end;
$function$;

revoke all on function public.claim_razorpay_payment_reconciliation(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.finish_razorpay_payment_reconciliation(
  uuid, uuid, text, text, integer, integer, text, jsonb, text, integer, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.record_reconciled_razorpay_capture(
  uuid, uuid, text, bigint, text, integer, integer, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.claim_razorpay_payment_reconciliation(uuid, text)
  to service_role;
grant execute on function public.finish_razorpay_payment_reconciliation(
  uuid, uuid, text, text, integer, integer, text, jsonb, text, integer, jsonb
) to service_role;
grant execute on function public.record_reconciled_razorpay_capture(
  uuid, uuid, text, bigint, text, integer, integer, text, jsonb
) to service_role;

comment on table public.razorpay_payment_reconciliation_runs is
  'Idempotent server-side Razorpay reconciliation decisions. Stores bounded, sanitized provider evidence summaries and digests, not raw provider payloads.';
comment on function public.record_reconciled_razorpay_capture(uuid, uuid, text, bigint, text, integer, integer, text, jsonb) is
  'Service-role-only atomic capture reconciliation. Calls the verified-payment transition and records its result under the active reconciliation lease.';

commit;
