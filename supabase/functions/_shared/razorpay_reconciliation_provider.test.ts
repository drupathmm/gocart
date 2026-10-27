import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { createRazorpayReconciliationReader } from './razorpay_reconciliation_provider.ts';

test('provider reconciliation reader performs only bounded GET lookups', async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const reader = createRazorpayReconciliationReader(
    'test-key-id',
    'test-key-secret',
    async (input, init) => {
      calls.push({ url: String(input), init });
      return new Response(JSON.stringify({ entity: 'fixture' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  );

  await reader.fetchProviderOrder('order with/?');
  await reader.fetchProviderOrderPayments('order with/?');
  await reader.fetchProviderPayment('pay with/?');

  assert.deepEqual(calls.map((call) => call.url), [
    'https://api.razorpay.com/v1/orders/order%20with%2F%3F',
    'https://api.razorpay.com/v1/orders/order%20with%2F%3F/payments',
    'https://api.razorpay.com/v1/payments/pay%20with%2F%3F',
  ]);
  for (const call of calls) {
    assert.equal(call.init?.method, 'GET');
    const headers = new Headers(call.init?.headers);
    assert.equal(headers.get('accept'), 'application/json');
    assert.equal(headers.get('authorization'), `Basic ${btoa('test-key-id:test-key-secret')}`);
    assert.ok(call.init?.signal instanceof AbortSignal);
  }
});

test('provider errors do not expose provider response bodies', async () => {
  const reader = createRazorpayReconciliationReader(
    'test-key-id',
    'test-key-secret',
    async () => new Response('provider error body must not escape', { status: 503 }),
  );

  await assert.rejects(reader.fetchProviderOrder('order-test'), (error: Error) => {
    assert.equal(error.message, 'PROVIDER_LOOKUP_FAILED');
    assert.equal(error.message.includes('provider error body'), false);
    return true;
  });
});

test('oversized provider responses are rejected before parsing', async () => {
  const reader = createRazorpayReconciliationReader(
    'test-key-id',
    'test-key-secret',
    async () => new Response('{}', {
      status: 200,
      headers: { 'Content-Length': '1000001' },
    }),
  );

  await assert.rejects(reader.fetchProviderOrder('order-test'), (error: Error) => {
    assert.equal(error.message, 'PROVIDER_RESPONSE_TOO_LARGE');
    return true;
  });
});
