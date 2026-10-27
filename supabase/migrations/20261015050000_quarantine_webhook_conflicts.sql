begin;

-- Keep conflicting, correctly signed deliveries auditable without replacing
-- the first-seen metadata or the active worker's lease token.
alter table public.razorpay_webhook_events
  add column conflict_count integer not null default 0,
  add column last_conflicting_event_type text,
  add column last_conflicting_provider_entity_id text,
  add constraint razorpay_webhook_events_conflict_count_check
    check (conflict_count >= 0);

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
    update public.razorpay_webhook_events e
    set conflict_count = least(e.conflict_count + 1, 2147483647),
        last_conflicting_event_type = p_event_type,
        last_conflicting_provider_entity_id = p_provider_entity_id,
        state = case when e.state = 'processing' then e.state else 'reconciliation_required' end,
        processed_at = null,
        last_error_code = 'WEBHOOK_EVENT_ID_CONFLICT'
    where e.event_id = p_event_id;
    return query select 'conflict'::text, null::uuid;
    return;
  end if;

  -- Once a delivery ID is known to conflict, stop automatic processing of
  -- either version until an operator investigates the recorded metadata.
  if v_event.conflict_count > 0 then
    return query select 'quarantined'::text, null::uuid;
    return;
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
  set state = case when e.conflict_count > 0 then 'reconciliation_required' else p_state end,
      processed_at = case when e.conflict_count = 0 and p_state = 'processed'
        then clock_timestamp() else null end,
      last_error_code = case when e.conflict_count > 0 then 'WEBHOOK_EVENT_ID_CONFLICT'
        when p_state = 'processed' then null else p_error_code end,
      lease_token = null,
      lease_expires_at = null
  where e.event_id = p_event_id
    and e.state = 'processing'
    and e.lease_token = p_lease_token;
  if not found then raise exception 'WEBHOOK_EVENT_LEASE_CONFLICT'; end if;
end;
$function$;

commit;
