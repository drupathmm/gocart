import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const container = 'supabase_db_gocart';
const nonce = randomUUID().replaceAll('-', '').slice(0, 12);
const buyer = randomUUID();
const keys = ['same', 'different', 'cancel', 'race'].map((x) => `cc_${nonce}_${x}`);
const products = ['same', 'different', 'cancel', 'race'].map((x) => `cc_${nonce}_${x}`);
const offers = ['cancel', 'race'].map((x) => `CC${nonce}${x.toUpperCase()}`);
const app = `gct${nonce}`;

function processResult(command, args, input = '') {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8').on('data', (x) => { stdout += x; });
    child.stderr.setEncoding('utf8').on('data', (x) => { stderr += x; });
    child.on('error', reject);
    child.on('close', (code) => code === 0
      ? resolve({ stdout, stderr })
      : reject(new Error(`${command} exited ${code}: ${stderr || stdout}`)));
    child.stdin.end(input);
  });
}

function launch(sql, appName) {
  const child = spawn('docker', [
    'exec', '-i', '-e', `PGAPPNAME=${appName}`, container,
    'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-A', '-t',
  ], { cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8').on('data', (x) => { stdout += x; });
  child.stderr.setEncoding('utf8').on('data', (x) => { stderr += x; });
  const result = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('close', (code) => code === 0
      ? resolve({ stdout, stderr })
      : reject(new Error(`psql exited ${code}: ${stderr || stdout}`)));
  });
  child.stdin.end(sql);
  return { child, result, output: () => `${stdout}\n${stderr}` };
}

const query = async (sql, appName = `${app}q`) => await launch(sql, appName).result;

async function verifyTarget() {
  const config = await readFile(path.join(root, 'supabase', 'config.toml'), 'utf8');
  assert.match(config, /^project_id\s*=\s*"gocart"\s*$/m);
  assert.match(config, /^port\s*=\s*54422\s*$/m);
  const inspect = await processResult('docker', [
    'inspect', '--format', '{{json .Config.Labels}}', container,
  ]);
  const labels = JSON.parse(inspect.stdout.trim());
  assert.equal(labels['com.supabase.cli.project'], 'gocart');
  assert.equal(path.resolve(labels['com.supabase.cli.workdir']), root);
  const port = await processResult('docker', ['port', container, '5432/tcp']);
  assert.match(port.stdout, /:54422\s/m);
  const id = await query("select json_build_object('db',current_database(),'port',current_setting('port'))::text;");
  assert.deepEqual(JSON.parse(id.stdout.trim()), { db: 'postgres', port: '5432' });
  const migration = await query(
    'select version from supabase_migrations.schema_migrations order by version desc limit 1;');
  assert.equal(migration.stdout.trim(), '20261015030000');
}

function setupSql() {
  const rows = products.map((name, i) => {
    const price = 10 + i;
    return `('${buyer}','${name}',${price},${price},${price},10,'Electronics')`;
  }).join(',');
  const checkouts = keys.map((key, i) => `
    insert into public.cart_items(user_id,product_id,quantity)
      select '${buyer}',id,${i > 1 ? 2 : 1} from public.products where name='${products[i]}';
    set local role authenticated;
    select public.checkout_place_order(${i === 2 ? `'${offers[0]}'` : i === 3 ? `'${offers[1]}'` : 'null'},'${key}');
    reset role;`).join('\n');
  const claims = keys.map((key, i) => `
    select id into v_order from public.orders where idempotency_key='${key}';
    select * into v_claim from public.claim_razorpay_order(v_order,'${buyer}');
    if v_claim.claim_state <> 'claimed' then raise exception 'claim failed'; end if;
    perform public.complete_razorpay_order(v_order,v_claim.claim_token,'rzp_${nonce}_${i}');`).join('\n');
  return `begin;
insert into auth.users(id,email) values('${buyer}','cc-${nonce}@example.invalid');
insert into public.profiles(id,name,email,role) values('${buyer}','Concurrency ${nonce}','ignore@example.invalid','user');
insert into public.products(merchant_id,name,original_price,offer_price,price,stock,category) values ${rows};
insert into public.offers(code,discount_type,discount_value,usage_limit,used_count)
values('${offers[0]}','percent',10,10,0),('${offers[1]}','percent',10,10,0);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','${buyer}',true);
${checkouts}
select set_config('request.jwt.claim.role','service_role',true);
set local role service_role;
do $setup$ declare v_order uuid; v_claim record; begin ${claims} end; $setup$;
commit;`;
}

async function waitForMarker(session, marker) {
  const end = Date.now() + 4000;
  while (!session.output().includes(marker)) {
    if (Date.now() > end) throw new Error(`Timed out waiting for ${marker}`);
    await new Promise((r) => setTimeout(r, 25));
  }
}

async function waitUntilBlocked(names) {
  const list = names.map((x) => `'${x}'`).join(',');
  const end = Date.now() + 4000;
  while (Date.now() < end) {
    const result = await query(`select count(*)::int from pg_stat_activity where application_name in (${list}) and wait_event_type='Lock';`);
    if (Number(result.stdout.trim()) === names.length) return;
    await new Promise((r) => setTimeout(r, 40));
  }
  throw new Error('Independent workers did not all wait on the held PostgreSQL row lock.');
}

function worker(kind, key, payment = '') {
  const i = keys.indexOf(key);
  const auth = kind === 'cancel'
    ? `select set_config('request.jwt.claim.role','authenticated',true); select set_config('request.jwt.claim.sub','${buyer}',true); set local role authenticated;`
    : `select set_config('request.jwt.claim.role','service_role',true); set local role service_role;`;
  const call = kind === 'cancel'
    ? `perform public.cancel_own_order((select id from public.orders where idempotency_key='${key}')); raise notice 'RESULT=CANCELLED';`
    : `perform public.record_verified_razorpay_payment((select id from public.orders where idempotency_key='${key}'),'${buyer}','rzp_${nonce}_${i}','${payment}',${[1000,1100,2340,2340][i]},'INR'); raise notice 'RESULT=CAPTURED';`;
  return `begin; ${auth} do $work$ begin ${call} exception when others then raise notice 'RESULT=ERROR:%:%',sqlstate,sqlerrm; end; $work$; commit;`;
}

async function race(key, calls) {
  const holder = launch(`begin; select id from public.orders where idempotency_key='${key}' for update; \\echo ROW_LOCK_HELD\nselect pg_sleep(3); commit;`, `${app}hold`);
  try {
    await waitForMarker(holder, 'ROW_LOCK_HELD');
    const sessions = calls.map((call, i) => {
      const name = `${app}w${i}`;
      return { name, session: launch(call.sql, name), expected: call.expected };
    });
    await waitUntilBlocked(sessions.map((x) => x.name));
    await holder.result;
    return await Promise.all(sessions.map(async ({ session, expected }) => {
      const { stdout, stderr } = await session.result;
      const result = `${stdout}\n${stderr}`.match(/RESULT=([^\r\n]+)/)?.[1];
      assert.ok(result, `${stdout}\n${stderr}`);
      assert.match(result, expected);
      return result;
    }));
  } finally {
    if (holder.child.exitCode === null) holder.child.kill();
    await holder.result.catch(() => {});
  }
}

async function state(key) {
  const { stdout } = await query(`select json_build_object(
    'status',o.status,'payment',o.payment_status,'attempt',a.state,'payment_id',a.provider_payment_id,
    'attempts',(select count(*)::int from public.razorpay_payment_attempts x where x.order_id=o.id),
    'items',(select count(*)::int from public.order_items x where x.order_id=o.id),
    'history_rows',(select count(*)::int from public.order_status_history h where h.order_id=o.id),
    'stock',p.stock,'offer_count',coalesce(f.used_count,0),
    'redemptions',(select count(*)::int from public.offer_redemptions r where r.order_id=o.id))::text
    from public.orders o join public.order_items i on i.order_id=o.id join public.products p on p.id=i.product_id
    left join public.offer_redemptions r on r.order_id=o.id left join public.offers f on f.id=r.offer_id
    left join public.razorpay_payment_attempts a on a.order_id=o.id where o.idempotency_key='${key}'
    group by o.id,p.id,f.id,a.id;`);
  return JSON.parse(stdout.trim());
}

async function cleanup() {
  const ks = keys.map((x) => `'${x}'`).join(',');
  const ps = products.map((x) => `'${x}'`).join(',');
  const os = offers.map((x) => `'${x}'`).join(',');
  await query(`begin;
alter table public.order_status_history disable trigger order_status_history_immutable;
delete from public.order_status_history where order_id in(select id from public.orders where idempotency_key in(${ks}));
alter table public.order_status_history enable trigger order_status_history_immutable;
delete from public.razorpay_refunds where attempt_id in(select id from public.razorpay_payment_attempts where order_id in(select id from public.orders where idempotency_key in(${ks})));
delete from public.razorpay_payment_attempts where order_id in(select id from public.orders where idempotency_key in(${ks}));
delete from public.offer_redemptions where order_id in(select id from public.orders where idempotency_key in(${ks}));
delete from public.order_items where order_id in(select id from public.orders where idempotency_key in(${ks}));
delete from public.orders where idempotency_key in(${ks});
delete from public.cart_items where user_id='${buyer}';
delete from public.products where name in(${ps});
delete from public.offers where code in(${os});
delete from public.profiles where id='${buyer}';
delete from auth.users where id='${buyer}';
commit;`, `${app}clean`);
}

async function main() {
  await verifyTarget();
  console.log('Verified local GoCart DB container, project label, port 54422, and migration version.');
  let setupDone = false;
  try {
    await query(setupSql(), `${app}setup`);
    setupDone = true;

    console.log('Concurrent same-payment verification');
    const sameResults = await race(keys[0], [
      { sql: worker('verify', keys[0], `pay_${nonce}_same`), expected: /^CAPTURED$/ },
      { sql: worker('verify', keys[0], `pay_${nonce}_same`), expected: /^CAPTURED$/ },
    ]);
    assert.deepEqual(sameResults.sort(), ['CAPTURED', 'CAPTURED']);
    const same = await state(keys[0]);
    assert.deepEqual([same.status, same.payment, same.attempt, same.attempts, same.items, same.payment_id],
      ['paid', 'paid', 'captured', 1, 1, `pay_${nonce}_same`]);

    console.log('Different payment IDs racing for one order');
    const differentResults = await race(keys[1], [
      { sql: worker('verify', keys[1], `pay_${nonce}_one`), expected: /^CAPTURED$/ },
      { sql: worker('verify', keys[1], `pay_${nonce}_two`), expected: /^ERROR:P0001:PAYMENT_ALREADY_ASSOCIATED$/ },
    ]);
    assert.equal(differentResults.filter((x) => x === 'CAPTURED').length, 1);
    assert.equal(differentResults.filter((x) => x.startsWith('ERROR:')).length, 1);
    const different = await state(keys[1]);
    assert.deepEqual([different.status, different.attempt, different.attempts, different.items],
      ['paid', 'captured', 1, 1]);
    assert.ok([`pay_${nonce}_one`, `pay_${nonce}_two`].includes(different.payment_id));

    console.log('Concurrent cancellation and exact inventory/offer restoration');
    const cancelledResults = await race(keys[2], [
      { sql: worker('cancel', keys[2]), expected: /^CANCELLED$/ },
      { sql: worker('cancel', keys[2]), expected: /^CANCELLED$/ },
    ]);
    assert.deepEqual(cancelledResults.sort(), ['CANCELLED', 'CANCELLED']);
    const cancelled = await state(keys[2]);
    assert.deepEqual([cancelled.status, cancelled.stock, cancelled.offer_count, cancelled.redemptions,
      cancelled.items, cancelled.history_rows], ['cancelled', 10, 0, 0, 1, 2]);

    console.log('Cancellation racing with payment verification');
    const raceResults = await race(keys[3], [
      { sql: worker('cancel', keys[3]), expected: /^CANCELLED$/ },
      { sql: worker('verify', keys[3], `pay_${nonce}_late`), expected: /^CAPTURED$/ },
    ]);
    const raced = await state(keys[3]);
    assert.equal(raced.status, 'cancelled');
    assert.deepEqual([raced.stock, raced.offer_count, raced.redemptions], [10, 0, 0]);
    assert.equal(raced.items, 1);
    assert.ok([2, 3].includes(raced.history_rows));
    assert.ok((raced.payment === 'paid' && raced.attempt === 'captured')
      || (raced.payment === 'payment_review' && raced.attempt === 'captured_review'));
    assert.ok(raceResults.includes('CAPTURED'));
    console.log(JSON.stringify({ samePayment: same, differentPaymentRace: different, concurrentCancellation: cancelled, cancellationVsVerification: raced }, null, 2));
    console.log('All independent-session race scenarios passed.');
  } finally {
    if (setupDone) {
      await cleanup();
      console.log('Removed only this run’s generated fixture and audit rows.');
    }
  }
}

await main();
