import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const container = 'supabase_db_gocart';
const nonce = randomUUID().replaceAll('-', '').slice(0, 16);
const eventId = `evt_webhook_race_${nonce}`;
const providerEntityId = `pay_webhook_race_${nonce}`;
const app = `gwh${nonce}`;

function run(command, args, input = '') {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      windowsHide: true,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8').on('data', (chunk) => { stdout += chunk; });
    child.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => code === 0
      ? resolve({ stdout, stderr })
      : reject(new Error(`${command} exited ${code}: ${stderr || stdout}`)));
    child.stdin.end(input);
  });
}

function session(sql, appName) {
  const child = spawn('docker', [
    'exec', '-i', '-e', `PGAPPNAME=${appName}`, container,
    'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-A', '-t',
  ], { cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8').on('data', (chunk) => { stdout += chunk; });
  child.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });
  const result = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('close', (code) => code === 0
      ? resolve({ stdout, stderr })
      : reject(new Error(`psql exited ${code}: ${stderr || stdout}`)));
  });
  child.stdin.end(sql);
  return { child, result, output: () => `${stdout}\n${stderr}` };
}

const query = async (sql, appName = `${app}q`) => await session(sql, appName).result;

async function verifyTarget() {
  const config = await readFile(path.join(root, 'supabase', 'config.toml'), 'utf8');
  assert.match(config, /^project_id\s*=\s*"gocart"\s*$/m);
  assert.match(config, /^port\s*=\s*54422\s*$/m);
  const { stdout } = await run('docker', [
    'inspect', '--format', '{{json .Config.Labels}}', container,
  ]);
  const labels = JSON.parse(stdout.trim());
  assert.equal(labels['com.supabase.cli.project'], 'gocart');
  assert.equal(path.resolve(labels['com.supabase.cli.workdir']), root);
  const port = await run('docker', ['port', container, '5432/tcp']);
  assert.match(port.stdout, /:54422\s/m);
  const identity = await query(
    "select json_build_object('db',current_database(),'port',current_setting('port'))::text;",
  );
  assert.deepEqual(JSON.parse(identity.stdout.trim()), { db: 'postgres', port: '5432' });
  const migration = await query(
    'select version from supabase_migrations.schema_migrations order by version desc limit 1;',
  );
  assert.equal(migration.stdout.trim(), '20261015060000');
}

async function waitForMarker(worker, marker) {
  const deadline = Date.now() + 5000;
  while (!worker.output().includes(marker)) {
    if (Date.now() > deadline) throw new Error(`Timed out waiting for ${marker}`);
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function waitUntilBlocked(names) {
  const quoted = names.map((name) => `'${name}'`).join(',');
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const { stdout } = await query(`
      select count(*)::int from pg_stat_activity
      where application_name in (${quoted}) and wait_event_type = 'Lock';
    `);
    if (Number(stdout.trim()) === names.length) return;
    await new Promise((resolve) => setTimeout(resolve, 30));
  }
  throw new Error('Both claim workers were not observed waiting on the same row lock.');
}

function claimSql() {
  return `begin;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select 'RESULT=' || claim_state || ':' || coalesce(lease_token::text,'')
from public.claim_razorpay_webhook_event('${eventId}','payment.captured','${providerEntityId}');
commit;`;
}

let fixtureCreated = false;
let lockHolder;
let workers = [];
try {
  await verifyTarget();
  console.log('Verified local GoCart project identity, database port 54422, and migration 20261015060000.');
  await query(`insert into public.razorpay_webhook_events(event_id,event_type,provider_entity_id)
    values ('${eventId}','payment.captured','${providerEntityId}');`, `${app}setup`);
  fixtureCreated = true;

  lockHolder = session(`begin;
select event_id from public.razorpay_webhook_events where event_id='${eventId}' for update;
\\echo WEBHOOK_ROW_LOCK_HELD
select pg_sleep(1.5);
commit;`, `${app}hold`);
  await waitForMarker(lockHolder, 'WEBHOOK_ROW_LOCK_HELD');

  workers = [0, 1].map((index) => session(claimSql(), `${app}w${index}`));
  await waitUntilBlocked([`${app}w0`, `${app}w1`]);
  await lockHolder.result;
  const results = await Promise.all(workers.map((worker) => worker.result));
  const claims = results.map(({ stdout, stderr }) => {
    const match = `${stdout}\n${stderr}`.match(/RESULT=(claimed|busy):([0-9a-f-]*)/i);
    assert.ok(match, `${stdout}\n${stderr}`);
    return { state: match[1], token: match[2] };
  });
  assert.equal(claims.filter((claim) => claim.state === 'claimed').length, 1);
  assert.equal(claims.filter((claim) => claim.state === 'busy').length, 1);

  const token = claims.find((claim) => claim.state === 'claimed').token;
  assert.match(token, /^[0-9a-f-]{36}$/i);
  const { stdout: stateJson } = await query(`select json_build_object(
    'state',state,'attempt_count',attempt_count,'lease_token',lease_token::text)::text
    from public.razorpay_webhook_events where event_id='${eventId}';`);
  const state = JSON.parse(stateJson.trim());
  assert.deepEqual(state, { state: 'processing', attempt_count: 1, lease_token: token });

  await query(`begin;
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
select public.finish_razorpay_webhook_event('${eventId}','${token}','processed',null);
commit;`, `${app}finish`);
console.log(JSON.stringify({ claims, finalEventState: 'processed', attemptCount: state.attempt_count }));
console.log('Concurrent duplicate delivery granted exactly one processing lease.');
} finally {
  if (lockHolder?.child.exitCode === null) lockHolder.child.kill();
  await lockHolder?.result.catch(() => {});
  await Promise.all(workers.map((worker) => worker.result.catch(() => {})));
  if (fixtureCreated) {
    await query(`delete from public.razorpay_webhook_events where event_id='${eventId}';`, `${app}clean`);
    console.log('Removed only this run’s generated webhook event row.');
  }
}
