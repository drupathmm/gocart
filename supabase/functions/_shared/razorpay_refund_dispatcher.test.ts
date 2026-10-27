import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  dispatchApprovedRefund,
  type MockableRazorpayRefundProvider,
  type RefundClaim,
  type RefundDispatchStore,
  type RefundRequestSnapshot,
} from './razorpay_refund_dispatcher.ts';

const snapshot: RefundRequestSnapshot = Object.freeze({
  refundId: 'refund-uuid-1', paymentId: 'pay_test_1', amountPaise: 4200,
  currency: 'INR', speed: 'normal', receipt: 'gcr_receipt_1',
  idempotencyKey: 'refund-uuid-1', approvalReference: 'approved-ticket-1',
  knownProviderRefundId: null,
});

function fixture(options: {
  claim?: () => Promise<RefundClaim>;
  provider?: Partial<MockableRazorpayRefundProvider>;
  recordFails?: boolean;
  approval?: string | null;
} = {}) {
  const calls: { create: unknown[]; fetch: unknown[]; list: number; records: unknown[]; unknown: unknown[]; reconciliation: unknown[] } = {
    create: [], fetch: [], list: 0, records: [], unknown: [], reconciliation: [],
  };
  let active = false;
  const store: RefundDispatchStore = {
    claim: async (refundId) => {
      if (options.claim) return options.claim();
      if (active) return { state: 'busy' };
      active = true;
      return {
        state: 'claimed', leaseToken: 'lease-1',
        request: { ...snapshot, refundId, approvalReference: options.approval === undefined
          ? snapshot.approvalReference : options.approval },
      };
    },
    recordValidatedResult: async (input) => {
      calls.records.push(input);
      if (options.recordFails) throw new Error('simulated db write failure');
      active = false;
    },
    markUnknown: async (input) => { calls.unknown.push(input); active = false; },
    recordReconciliation: async (input) => { calls.reconciliation.push(input); },
  };
  const validResponse = {
    id: 'rfnd_test_1', payment_id: snapshot.paymentId, amount: snapshot.amountPaise,
    currency: snapshot.currency, receipt: snapshot.receipt, status: 'pending',
  };
  const provider: MockableRazorpayRefundProvider = {
    createRefund: async (input) => {
      calls.create.push(input);
      return { httpStatus: 200, body: validResponse };
    },
    listRefunds: async () => { calls.list++; return []; },
    fetchRefund: async (paymentId, refundId) => {
      calls.fetch.push({ paymentId, refundId });
      return { ...validResponse, id: refundId };
    },
    ...options.provider,
  };
  return { store, provider, calls, validResponse };
}

test('dispatch sends the immutable body and stable idempotency key; pending is not completion', async () => {
  const f = fixture();
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.deepEqual(f.calls.create, [{
    paymentId: snapshot.paymentId,
    idempotencyKey: snapshot.idempotencyKey,
    body: { amount: snapshot.amountPaise, speed: snapshot.speed, receipt: snapshot.receipt },
  }]);
  assert.equal(result.state, 'submitted');
  assert.equal(result.providerStatus, 'pending');
});

test('an unapproved intent never calls the provider', async () => {
  const f = fixture({ approval: null });
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.deepEqual(result, { state: 'approval_required' });
  assert.equal(f.calls.create.length, 0);
});

test('active concurrent dispatch claim prevents a second provider submission', async () => {
  let release!: () => void;
  const wait = new Promise<void>((resolve) => { release = resolve; });
  let calls = 0;
  const f = fixture({ provider: { createRefund: async () => {
    calls++;
    await wait;
    return { httpStatus: 200, body: f.validResponse };
  } } });
  const first = dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  await Promise.resolve();
  const second = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  release();
  const firstResult = await first;
  assert.deepEqual(second, { state: 'busy' });
  assert.equal(calls, 1);
  assert.equal(firstResult.state, 'submitted');
});

test('timeout before or after acceptance remains unknown and reuses the same request on retry', async () => {
  for (const accepted of [false, true]) {
    const f = fixture({ provider: { createRefund: async (input) => {
      f.calls.create.push(input);
      if (accepted) f.calls.list = 1; // mock provider accepted before the response was lost
      throw new Error('timeout');
    } } });
    const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
    assert.equal(result.state, 'unknown');
    await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
    assert.equal(f.calls.create.length, 2);
    assert.equal(JSON.stringify(f.calls.create[0]), JSON.stringify({
      paymentId: snapshot.paymentId, idempotencyKey: snapshot.idempotencyKey,
      body: { amount: snapshot.amountPaise, speed: snapshot.speed, receipt: snapshot.receipt },
    }));
    assert.equal(JSON.stringify(f.calls.create[1]), JSON.stringify(f.calls.create[0]));
    assert.equal((f.calls.unknown[0] as { reason: string }).reason, 'PROVIDER_REQUEST_OUTCOME_UNKNOWN');
  }
});

test('409 performs diagnostic listing but does not infer success or submit another intent', async () => {
  const f = fixture({ provider: {
    createRefund: async () => ({ httpStatus: 409 }),
    listRefunds: async () => [{ ...f.validResponse, id: 'rfnd_possible_match' }],
  } });
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.equal(result.state, 'unknown');
  assert.equal(f.calls.create.length, 0);
  assert.equal(f.calls.reconciliation.length, 1);
  assert.deepEqual(f.calls.unknown.map((x) => (x as { reason: string }).reason), ['PROVIDER_IDEMPOTENCY_CONFLICT']);
});

test('database failure after provider acceptance preserves unknown state', async () => {
  const f = fixture({ recordFails: true });
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.equal(result.state, 'unknown');
  assert.equal(f.calls.create.length, 1);
  assert.equal((f.calls.unknown[0] as { reason: string }).reason, 'DATABASE_RESULT_WRITE_FAILED');
});

test('mismatched provider identity, amount, currency, receipt, and unsupported statuses are rejected', async (t) => {
  const variants = [
    ['payment', { payment_id: 'pay_other' }], ['refund ID', { id: '' }],
    ['amount', { amount: 4199 }], ['currency', { currency: 'USD' }],
    ['receipt', { receipt: 'other' }], ['status', { status: 'created' }],
  ] as const;
  for (const [label, override] of variants) {
    await t.test(label, async () => {
      const f = fixture({ provider: { createRefund: async () => ({
        httpStatus: 200, body: { ...f.validResponse, ...override },
      }) } });
      const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
      assert.equal(result.state, 'unknown');
      assert.equal(f.calls.records.length, 0);
      assert.equal(f.calls.reconciliation.length, 1);
    });
  }
});

test('receipt-less legacy intent is blocked before provider execution', async () => {
  const f = fixture({ claim: async () => ({ state: 'reconciliation_required' }) });
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.deepEqual(result, { state: 'reconciliation_required' });
  assert.equal(f.calls.create.length, 0);
});

test('non-success HTTP responses remain ambiguous and are not recorded as provider outcomes', async () => {
  const f = fixture({ provider: { createRefund: async () => ({ httpStatus: 500 }) } });
  const result = await dispatchApprovedRefund(snapshot.refundId, f.store, f.provider);
  assert.equal(result.state, 'unknown');
  assert.equal(f.calls.records.length, 0);
});
