import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { dispatchAfterClaim } from './razorpay_order_dispatch.ts';

test('provider request starts only after the durable dispatch marker', async () => {
  const calls: string[] = [];
  const result = await dispatchAfterClaim(
    async () => {
      calls.push('mark');
      return {};
    },
    async () => {
      calls.push('provider');
      return 'created';
    },
  );

  assert.deepEqual(calls, ['mark', 'provider']);
  assert.deepEqual(result, { state: 'dispatched', response: 'created' });
});

test('provider request is skipped when the marker cannot be committed', async () => {
  let providerCalled = false;
  const result = await dispatchAfterClaim(
    async () => ({ error: new Error('claim expired') }),
    async () => {
      providerCalled = true;
      return 'created';
    },
  );

  assert.equal(providerCalled, false);
  assert.deepEqual(result, { state: 'not_marked' });
});

test('provider request is skipped when marking throws', async () => {
  let providerCalled = false;
  const result = await dispatchAfterClaim(
    async () => { throw new Error('database unavailable'); },
    async () => {
      providerCalled = true;
      return 'created';
    },
  );

  assert.equal(providerCalled, false);
  assert.deepEqual(result, { state: 'not_marked' });
});
