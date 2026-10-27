begin;

-- The existing event ledger deduplicates inserts but cannot distinguish an
-- active worker from an interrupted one. A short lease makes claims atomic
-- and permits retry after a worker disappears without deleting audit rows.
alter table public.razorpay_webhook_events
  add column lease_token uuid,
  add column lease_expires_at timestamptz,
  add column attempt_count integer not null default 0;

-- Any pre-existing processing row has no lease and is recoverable immediately.
update public.razorpay_webhook_events
set state = 'reconciliation_required'
where state = 'processing';

alter table public.razorpay_webhook_events
  add constraint razorpay_webhook_events_attempt_count_check
    check (attempt_count >= 0),
  add constraint razorpay_webhook_events_lease_check
    check ((state = 'processing' and lease_token is not null and lease_expires_at is not null)
      or (state <> 'processing' and lease_token is null and lease_expires_at is null));

create or replace function public.claim_razorpay_webhook_event(
  p_event_id text,
  p_event_type text,
  p_provider_entity_id text
)
returns table (claim_state text, lease_token uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event public.razorpay_webhook_events%rowtype;
  v_token uuid;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'NOT_AUTHORIZED';
  end if;
  if p_event_id is null or length(p_event_id) not between 1 and 200
     or p_event_type is null or length(p_event_type) not between 1 and 200
     or (p_provider_entity_id is not null and length(p_provider_entity_id) > 200) then
    raise exception 'INVALID_WEBHOOK_EVENT';
  end if;

  insert into public.razorpay_webhook_events (event_id, event_type, provider_entity_id)
  values (p_event_id, p_event_type, p_provider_entity_id)
  on conflict (event_id) do nothing;

  select * into v_event from public.razorpay_webhook_events e
  where e.event_id = p_event_id for update;
  if v_event.event_type is distinct from p_event_type
     or v_event.provider_entity_id is distinct from p_provider_entity_id then
    raise exception 'WEBHOOK_EVENT_ID_CONFLICT';
  end if;
  if v_event.state = 'processed' then
    return query select 'processed'::text, null::uuid;
    return;
  end if;
  if v_event.state = 'processing'
     and v_event.lease_expires_at > clock_timestamp() then
    return query select 'busy'::text, null::uuid;
    return;
  end if;

  v_token := gen_random_uuid();
  update public.razorpay_webhook_events e
  set state = 'processing', lease_token = v_token,
      lease_expires_at = clock_timestamp() + interval '2 minutes',
      attempt_count = e.attempt_count + 1, last_error_code = null
  where e.event_id = p_event_id;
  return query select 'claimed'::text, v_token;
end;
$function$;

create or replace function public.finish_razorpay_webhook_event(
  p_event_id text,
  p_lease_token uuid,
  p_state text,
  p_error_code text default null
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
  if p_state is null or p_state not in ('processed', 'reconciliation_required', 'failed')
     or (p_error_code is not null and length(p_error_code) > 100) then
    raise exception 'INVALID_WEBHOOK_EVENT_STATE';
  end if;

  update public.razorpay_webhook_events e
  set state = p_state,
      processed_at = case when p_state = 'processed' then clock_timestamp() else null end,
      last_error_code = case when p_state = 'processed' then null else p_error_code end,
      lease_token = null,
      lease_expires_at = null
  where e.event_id = p_event_id
    and e.state = 'processing'
    and e.lease_token = p_lease_token;
  if not found then raise exception 'WEBHOOK_EVENT_LEASE_CONFLICT'; end if;
end;
$function$;

revoke all on function public.claim_razorpay_webhook_event(text, text, text)
  from public, anon, authenticated;
revoke all on function public.finish_razorpay_webhook_event(text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.claim_razorpay_webhook_event(text, text, text)
  to service_role;
grant execute on function public.finish_razorpay_webhook_event(text, uuid, text, text)
  to service_role;

commit;
