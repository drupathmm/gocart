import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const databaseContainer = 'supabase_db_gocart';
const expectedDatabasePort = '54422';

export const reconciliationSql = String.raw`
begin read only;
with
expired_leases as (
  select event_id, event_type, state, attempt_count, last_error_code,
         received_at, lease_expires_at, conflict_count
  from public.razorpay_webhook_events
  where state = 'processing' and lease_expires_at <= clock_timestamp()
  order by lease_expires_at
  limit 100
),
retryable_events as (
  select event_id, event_type, state, attempt_count, last_error_code,
         received_at, lease_expires_at, conflict_count
  from public.razorpay_webhook_events
  where state in ('received', 'reconciliation_required')
    and conflict_count = 0
    and last_error_code is distinct from 'WEBHOOK_EVENT_ID_CONFLICT'
  order by received_at
  limit 100
),
quarantined_events as (
  select event_id, event_type, provider_entity_id, state, attempt_count,
         last_error_code, received_at, conflict_count,
         last_conflicting_event_type, last_conflicting_provider_entity_id
  from public.razorpay_webhook_events
  where state = 'failed' or conflict_count > 0
  order by received_at
  limit 100
),
captured_reviews as (
  select a.id as attempt_id, a.order_id, a.state as attempt_state,
         o.status as order_status, o.payment_status,
         case
           when a.state = 'captured_review' then 'captured_after_cancellation_review'
           when o.id is null then 'order_missing'
           when o.status is distinct from 'paid' or o.payment_status is distinct from 'paid'
             then 'captured_attempt_order_state_mismatch'
         end as reason
  from public.razorpay_payment_attempts a
  left join public.orders o on o.id = a.order_id
  where a.state = 'captured_review'
     or (a.state = 'captured'
       and (o.id is null or o.status is distinct from 'paid'
         or o.payment_status is distinct from 'paid'))
  order by a.updated_at
  limit 100
),
payment_mismatches as (
  select a.id as attempt_id, a.order_id,
         (a.expected_amount_paise is distinct from round(o.total_amount * 100)::bigint)
           as amount_mismatch,
         (a.currency is distinct from 'INR') as currency_mismatch,
         (a.provider_order_id is distinct from o.razorpay_order_id)
           as provider_order_id_mismatch,
         (a.state = 'captured' and (o.status is distinct from 'paid'
           or o.payment_status is distinct from 'paid')) as captured_state_mismatch
  from public.razorpay_payment_attempts a
  join public.orders o on o.id = a.order_id
  where a.expected_amount_paise is distinct from round(o.total_amount * 100)::bigint
     or a.currency is distinct from 'INR'
     or a.provider_order_id is distinct from o.razorpay_order_id
     or (a.state = 'captured' and (o.status is distinct from 'paid'
       or o.payment_status is distinct from 'paid'))
  order by a.updated_at
  limit 100
)
select jsonb_build_object(
  'transaction_read_only', current_setting('transaction_read_only') = 'on',
  'generated_at', clock_timestamp(),
  'expired_processing_leases', coalesce((
    select jsonb_agg(to_jsonb(x)) from expired_leases x
  ), '[]'::jsonb),
  'retryable_events', coalesce((
    select jsonb_agg(to_jsonb(x)) from retryable_events x
  ), '[]'::jsonb),
  'quarantined_payment_events', coalesce((
    select jsonb_agg(jsonb_build_object(
      'event_id', x.event_id,
      'event_type', x.event_type,
      'state', x.state,
      'attempt_count', x.attempt_count,
      'last_error_code', x.last_error_code,
      'received_at', x.received_at,
      'conflict_count', x.conflict_count,
      'last_conflicting_event_type', x.last_conflicting_event_type,
      'provider_entity_reference', case
        when x.provider_entity_id is null then null
        when length(x.provider_entity_id) > 8
          then left(x.provider_entity_id, 4) || '…' || right(x.provider_entity_id, 4)
        else '[redacted]'
      end,
      'conflicting_provider_reference', case
        when x.last_conflicting_provider_entity_id is null then null
        when length(x.last_conflicting_provider_entity_id) > 8
          then left(x.last_conflicting_provider_entity_id, 4) || '…'
            || right(x.last_conflicting_provider_entity_id, 4)
        else '[redacted]'
      end
    ))
    from quarantined_events x
    where x.event_type like 'payment.%' or x.event_type like 'refund.%'
       or x.last_conflicting_event_type like 'payment.%'
       or x.last_conflicting_event_type like 'refund.%'
       or x.last_error_code in (
         'MALFORMED_SIGNED_BODY', 'INVALID_EVENT_PAYLOAD', 'MISSING_EVENT_ID',
         'INVALID_EVENT_ID', 'UNSUPPORTED_EVENT_TYPE', 'UNSUPPORTED_REFUND_STATE',
         'WEBHOOK_EVENT_ID_CONFLICT'
       )
  ), '[]'::jsonb),
  'captured_attempts_needing_review', coalesce((
    select jsonb_agg(to_jsonb(x)) from captured_reviews x
  ), '[]'::jsonb),
  'payment_order_mismatches', coalesce((
    select jsonb_agg(to_jsonb(x)) from payment_mismatches x
  ), '[]'::jsonb)
)::text;
commit;
`;

function run(command, args) {
  return execFileSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
  }).trim();
}

function assertLocalGoCartTarget() {
  const config = readFileSync(new URL('../supabase/config.toml', import.meta.url), 'utf8');
  if (!/^project_id\s*=\s*["']gocart["']/m.test(config)) {
    throw new Error('Local Supabase project_id is not gocart.');
  }
  const dbSection = config.split(/\r?\n(?=\[)/).find((section) => section.startsWith('[db]')) ?? '';
  if (!new RegExp(`^port\\s*=\\s*${expectedDatabasePort}$`, 'm').test(dbSection)) {
    throw new Error('Local GoCart database port does not match the expected isolated port.');
  }

  const projectLabel = run('docker', [
    'inspect', '--format', '{{index .Config.Labels "com.supabase.cli.project"}}', databaseContainer,
  ]);
  if (projectLabel !== 'gocart') {
    throw new Error('The selected database container is not labeled as the GoCart project.');
  }
  const portMapping = run('docker', [
    'inspect', '--format', '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}',
    databaseContainer,
  ]);
  if (portMapping !== expectedDatabasePort) {
    throw new Error('The GoCart database container is not bound to its expected local port.');
  }
}

export function parseReport(output) {
  const report = JSON.parse(output);
  if (report.transaction_read_only !== true) {
    throw new Error('PostgreSQL did not confirm a read-only transaction.');
  }
  return report;
}

export function summarizeReport(report) {
  return Object.fromEntries([
    'expired_processing_leases',
    'retryable_events',
    'quarantined_payment_events',
    'captured_attempts_needing_review',
    'payment_order_mismatches',
  ].map((key) => [key, report[key]?.length ?? 0]));
}

export function runReconciliationReport() {
  assertLocalGoCartTarget();
  const result = run('docker', [
    'exec', '-i', databaseContainer,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', 'postgres', '-c', reconciliationSql,
  ]);
  return parseReport(result);
}

if (process.argv[1] && fileURLToPath(import.meta.url).toLowerCase()
  === resolve(process.argv[1]).toLowerCase()) {
  try {
    const report = runReconciliationReport();
    console.log(JSON.stringify({ ...report, summary: summarizeReport(report) }, null, 2));
  } catch (error) {
    console.error(`Reconciliation report failed: ${error.message}`);
    process.exitCode = 1;
  }
}
