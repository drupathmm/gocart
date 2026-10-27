import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  digestRazorpayEvidence,
  handleRazorpayReconciliation,
  normalizeRazorpayEvidence,
  type PaymentCollection,
  type ProviderOrder,
  type ProviderPayment,
  type RazorpayReconciliationDependencies,
  type ReconciliationClaim,
} from './razorpay_reconciliation_handler.ts';

const orderId = 'c4a4ed6d-b105-4f75-94a7-947e6ea8ded8';
const providerOrderId = 'order_test_reconcile_1';
const paymentId = 'pay_test_reconcile_1';
const serviceRoleKey = 'reconciliation-test-only-key';
const amount = 7250;

const defaultOrder: ProviderOrder = {
  id: providerOrderId,
  receipt: orderId,
  status: 'attempted',
  amount,
  amount_paid: 0,
  amount_due: amount,
  currency: 'INR',
  attempts: 1,
};

const failedPayment: ProviderPayment = {
  entity: 'payment',
  id: paymentId,
  order_id: providerOrderId,
  amount,
  currency: 'INR',
  status: 'failed',
  captured: false,
  refund_status: null,
  amount_refunded: 0,
};

const capturedPayment: ProviderPayment = {
  ...failedPayment,
  status: 'captured',
  captured: true,
  amount_captured: amount,
};

function defaultClaim(overrides: Partial<ReconciliationClaim> = {}): ReconciliationClaim {
  return {
    claim_state: 'claimed',
    run_id: 'run-1',
    claim_token: 'claim-token-1',
    attempt_id: 'attempt-1',
    provider_order_id: providerOrderId,
    expected_amount_paise: amount,
    currency: 'INR',
    order_status: 'pending',
    payment_status: 'unpaid',
    cached_response: null,
    cached_http_status: null,
    attempt_state: 'created',
    existing_provider_payment_id: null,
    ...overrides,
  };
}

function fixture(overrides: Partial<RazorpayReconciliationDependencies> = {}) {
  const counts = { claim: 0, order: 0, collection: 0, payment: 0, finish: 0, capture: 0 };
  let claim = defaultClaim();
  let providerOrder: ProviderOrder = { ...defaultOrder };
  let collection: PaymentCollection = {
    entity: 'collection', count: 1, items: [{ ...failedPayment }],
  };
  let detail: ProviderPayment = { ...capturedPayment };
  let dependencies: RazorpayReconciliationDependencies = {
    configured: true,
    serviceRoleKey,
    claim: async () => { counts.claim++; return { claim }; },
    fetchProviderOrder: async () => { counts.order++; return providerOrder; },
    fetchProviderOrderPayments: async () => { counts.collection++; return collection; },
    fetchProviderPayment: async () => { counts.payment++; return detail; },
    finishDecision: async (input) => {
      counts.finish++;
      return { response_payload: input.responsePayload, http_status: input.httpStatus };
    },
    recordCapturedPayment: async (input) => {
      counts.capture++;
      return {
        response_payload: {
          order_id: orderId,
          status: 'paid',
          payment_status: 'paid',
          reconciliation_result: 'captured',
          reservation_action: 'none',
        },
        http_status: 200,
      };
    },
    ...overrides,
  };
  return {
    counts,
    dependencies,
    setClaim(value: ReconciliationClaim) { claim = value; },
    setProviderOrder(value: ProviderOrder) { providerOrder = value; },
    setCollection(value: PaymentCollection) { collection = value; },
    setDetail(value: ProviderPayment) { detail = value; },
  };
}

function request(options: {
  authorization?: string;
  idempotencyKey?: string;
  body?: unknown;
} = {}): Request {
  return new Request('https://local.invalid/reconcile', {
    method: 'POST',
    headers: {
      ...(options.authorization === undefined
        ? { Authorization: `Bearer ${serviceRoleKey}` }
        : { Authorization: options.authorization }),
      ...(options.idempotencyKey === undefined
        ? { 'Idempotency-Key': 'reconcile-key-0001' }
        : { 'Idempotency-Key': options.idempotencyKey }),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(options.body ?? { order_id: orderId }),
  });
}

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

test('rejects callers without the trusted service credential before claiming', async () => {
  const state = fixture();
  const response = await handleRazorpayReconciliation(
    request({ authorization: 'Bearer user-token' }), state.dependencies,
  );
  assert.equal(response.status, 401);
  assert.equal(state.counts.claim, 0);
  assert.equal(state.counts.order, 0);
});

test('rejects missing idempotency keys before claiming', async () => {
  const state = fixture();
  const response = await handleRazorpayReconciliation(
    request({ idempotencyKey: 'short' }), state.dependencies,
  );
  assert.equal(response.status, 400);
  assert.equal(state.counts.claim, 0);
});

test('rejects caller-supplied payment and noncapture evidence fields', async () => {
  const state = fixture();
  const response = await handleRazorpayReconciliation(request({
    body: { order_id: orderId, captured: true, noncaptured: true },
  }), state.dependencies);
  assert.equal(response.status, 400);
  assert.equal(state.counts.claim, 0);
  assert.equal(state.counts.capture, 0);
});

test('a pending order and failed attempt remain held without noncapture release', async () => {
  const state = fixture();
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(response.status, 200);
  assert.equal(body.reconciliation_result, 'noncapture_unconfirmed');
  assert.equal(body.reservation_action, 'none');
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});

test('a provider order with no payment attempts remains unconfirmed and held', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, status: 'created', attempts: 0 });
  state.setCollection({ entity: 'collection', count: 0, items: [] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'noncapture_unconfirmed');
  assert.equal(state.counts.capture, 0);
});

test('a failed payment list is not treated as terminal order noncapture', async () => {
  const state = fixture();
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'noncapture_unconfirmed');
  assert.equal(state.counts.capture, 0);
});

test('a matching captured payment is recorded through the atomic capture RPC', async () => {
  const state = fixture();
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  const captureInputs: Parameters<RazorpayReconciliationDependencies['recordCapturedPayment']>[0][] = [];
  const response = await handleRazorpayReconciliation(request(), {
    ...state.dependencies,
    recordCapturedPayment: async (input) => {
      state.counts.capture++;
      captureInputs.push(input);
      return {
        response_payload: {
          order_id: orderId,
          status: 'paid',
          payment_status: 'paid',
          reconciliation_result: 'captured',
          reservation_action: 'none',
        },
        http_status: 200,
      };
    },
  });
  const body = await responseJson(response);
  assert.equal(response.status, 200);
  assert.equal(body.reconciliation_result, 'captured');
  assert.equal(state.counts.payment, 1);
  assert.equal(state.counts.capture, 1);
  assert.equal(captureInputs[0]?.providerPaymentId, paymentId);
  assert.equal(captureInputs[0]?.amountPaise, amount);
  assert.match(captureInputs[0]?.evidenceSha256 ?? '', /^[a-f0-9]{64}$/);
  assert.equal(
    (captureInputs[0]?.evidenceSummary.order as Record<string, unknown>).receipt,
    orderId,
  );
  assert.equal(
    (captureInputs[0]?.evidenceSummary.payment_collection as { payments: { status: string }[] })
      .payments[0]?.status,
    'captured',
  );
});

test('a captured payment is held when another provider attempt is unresolved', async (t) => {
  for (const siblingStatus of ['created', 'authorized', 'failed']) {
    await t.test(`${siblingStatus} sibling`, async () => {
      const state = fixture();
      state.setProviderOrder({
        ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0, attempts: 2,
      });
      state.setCollection({
        entity: 'collection', count: 2,
        items: [
          { ...capturedPayment },
          { ...failedPayment, id: `pay_test_sibling_${siblingStatus}`, status: siblingStatus },
        ],
      });
      let decision: string | null = null;
      const response = await handleRazorpayReconciliation(request(), {
        ...state.dependencies,
        finishDecision: async (input) => {
          decision = input.decision;
          state.counts.finish++;
          return { response_payload: input.responsePayload, http_status: input.httpStatus };
        },
      });
      const body = await responseJson(response);
      assert.equal(decision, 'review_required');
      assert.equal(body.reconciliation_result, 'manual_review');
      assert.equal(body.reservation_action, 'none');
      assert.equal(state.counts.payment, 0);
      assert.equal(state.counts.capture, 0);
    });
  }
});

test('an incomplete sibling payment prevents normal capture reconciliation', async () => {
  const state = fixture();
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0, attempts: 2,
  });
  state.setCollection({
    entity: 'collection', count: 2,
    items: [
      { ...capturedPayment },
      { ...failedPayment, id: 'pay_test_incomplete_sibling', entity: undefined, status: 'authorized' },
    ],
  });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(body.reservation_action, 'none');
  assert.equal(state.counts.payment, 0);
  assert.equal(state.counts.capture, 0);
});

test('duplicate captured entries are quarantined instead of recorded twice', async () => {
  const state = fixture();
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0, attempts: 2,
  });
  state.setCollection({
    entity: 'collection', count: 2,
    items: [{ ...capturedPayment }, { ...capturedPayment }],
  });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.payment, 0);
  assert.equal(state.counts.capture, 0);
});

test('a provider payment ID conflicting with the captured local ID is held for review', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({
    attempt_state: 'captured',
    existing_provider_payment_id: 'pay_test_previously_recorded',
  }));
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'captured_payment_requires_manual_review');
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});

test('canonical evidence digest binds collection metadata and normalizes item order', async () => {
  const order = { ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0, attempts: 2 };
  const items = [{ ...capturedPayment }, { ...failedPayment, id: 'pay_test_failed_sibling' }];
  const context = {
    orderId,
    providerOrderId,
    expectedAmountPaise: amount,
    currency: 'INR',
    attemptId: 'attempt-1',
    localOrderStatus: 'pending',
    localPaymentStatus: 'unpaid',
    localAttemptState: 'created',
    existingProviderPaymentId: null,
  };
  const first = await normalizeRazorpayEvidence(order, {
    entity: 'collection', count: 2, items,
  }, capturedPayment, context);
  const reordered = await normalizeRazorpayEvidence(order, {
    entity: 'collection', count: 2, items: [...items].reverse(),
  }, capturedPayment, context);
  const changedCount = await normalizeRazorpayEvidence(order, {
    entity: 'collection', count: 1, items,
  }, capturedPayment, context);
  const firstDigest = await digestRazorpayEvidence(first.envelope);
  const reorderedDigest = await digestRazorpayEvidence(reordered.envelope);
  const changedDigest = await digestRazorpayEvidence(changedCount.envelope);

  assert.equal(first.oversized, false);
  assert.deepEqual(first.summary, first.envelope);
  assert.equal(firstDigest, reorderedDigest);
  assert.notEqual(firstDigest, changedDigest);
});

test('canonical evidence hashes long decision fields without persisting their raw values', async () => {
  const longPaymentId = `pay_${'a'.repeat(300)}`;
  const changedPaymentId = `pay_${'a'.repeat(299)}b`;
  const order = { ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0 };
  const context = {
    orderId,
    providerOrderId,
    expectedAmountPaise: amount,
    currency: 'INR',
    attemptId: 'attempt-1',
    localOrderStatus: 'pending',
    localPaymentStatus: 'unpaid',
    localAttemptState: 'created',
    existingProviderPaymentId: null,
  };
  const first = await normalizeRazorpayEvidence(order, {
    entity: 'collection', count: 1,
    items: [{ ...capturedPayment, id: longPaymentId }],
  }, null, context);
  const changed = await normalizeRazorpayEvidence(order, {
    entity: 'collection', count: 1,
    items: [{ ...capturedPayment, id: changedPaymentId }],
  }, null, context);

  assert.notEqual(
    await digestRazorpayEvidence(first.envelope),
    await digestRazorpayEvidence(changed.envelope),
  );
  assert.equal(JSON.stringify(first.summary).includes(longPaymentId), false);
});

test('valid zero-refund metadata is accepted while positive refunds require review', async (t) => {
  const cases: Array<{ name: string; payment: ProviderPayment; expected: string }> = [
    {
      name: 'zero refund',
      payment: { ...capturedPayment, refund_status: null, amount_refunded: 0 },
      expected: 'captured',
    },
    {
      name: 'positive partial refund',
      payment: { ...capturedPayment, refund_status: 'partial', amount_refunded: 1 },
      expected: 'manual_review',
    },
  ];
  for (const item of cases) {
    await t.test(item.name, async () => {
      const state = fixture();
      state.setProviderOrder({
        ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
      });
      state.setCollection({ entity: 'collection', count: 1, items: [item.payment] });
      const response = await handleRazorpayReconciliation(request(), state.dependencies);
      const body = await responseJson(response);
      assert.equal(body.reconciliation_result, item.expected);
      assert.equal(state.counts.capture, item.expected === 'captured' ? 1 : 0);
    });
  }
});

test('malformed and contradictory refund metadata is routed to review', async (t) => {
  const cases: Array<{ name: string; payment: ProviderPayment }> = [
    { name: 'numeric string amount', payment: { ...capturedPayment, amount_refunded: '1' } },
    { name: 'negative amount', payment: { ...capturedPayment, amount_refunded: -1 } },
    { name: 'boolean amount', payment: { ...capturedPayment, amount_refunded: true } },
    { name: 'wrong refund status type', payment: { ...capturedPayment, refund_status: 1 } },
    { name: 'amount exceeds payment amount', payment: { ...capturedPayment, amount_refunded: amount + 1 } },
    {
      name: 'partial status with full amount',
      payment: { ...capturedPayment, refund_status: 'partial', amount_refunded: amount },
    },
    {
      name: 'full status with partial amount',
      payment: { ...capturedPayment, refund_status: 'full', amount_refunded: 1 },
    },
    {
      name: 'null status with positive amount',
      payment: { ...capturedPayment, refund_status: null, amount_refunded: 1 },
    },
  ];
  for (const item of cases) {
    await t.test(item.name, async () => {
      const state = fixture();
      state.setProviderOrder({
        ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
      });
      state.setCollection({ entity: 'collection', count: 1, items: [item.payment] });
      const response = await handleRazorpayReconciliation(request(), state.dependencies);
      const body = await responseJson(response);
      assert.equal(body.reconciliation_result, 'manual_review');
      assert.equal(state.counts.capture, 0);
    });
  }
});

test('malformed refund metadata on the fetched payment detail prevents capture recording', async () => {
  const state = fixture();
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  state.setDetail({ ...capturedPayment, refund_status: 'full', amount_refunded: amount - 1 });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.capture, 0);
});

test('a late capture can be recorded for review without reopening cancelled fulfillment', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({ order_status: 'cancelled', payment_status: 'cancelled' }));
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  const response = await handleRazorpayReconciliation(request(), {
    ...state.dependencies,
    recordCapturedPayment: async () => {
      state.counts.capture++;
      return {
        response_payload: {
          order_id: orderId,
          status: 'cancelled',
          payment_status: 'payment_review',
          reconciliation_result: 'review_required',
          reservation_action: 'none',
        },
        http_status: 200,
      };
    },
  });
  const body = await responseJson(response);
  assert.equal(body.status, 'cancelled');
  assert.equal(body.payment_status, 'payment_review');
  assert.equal(state.counts.capture, 1);
});

test('a late capture after verified noncapture is recorded through the cancelled-order review path', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({
    attempt_state: 'noncaptured',
    order_status: 'cancelled',
    payment_status: 'cancelled',
  }));
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  const response = await handleRazorpayReconciliation(request(), {
    ...state.dependencies,
    recordCapturedPayment: async () => {
      state.counts.capture++;
      return {
        response_payload: {
          order_id: orderId,
          status: 'cancelled',
          payment_status: 'payment_review',
          reconciliation_result: 'review_required',
          reservation_action: 'none',
        },
        http_status: 200,
      };
    },
  });
  const body = await responseJson(response);
  assert.equal(response.status, 200);
  assert.equal(body.status, 'cancelled');
  assert.equal(body.payment_status, 'payment_review');
  assert.equal(state.counts.capture, 1);
});

test('a capture already in captured_review stays in review without repeating the transition', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({
    attempt_state: 'captured_review',
    existing_provider_payment_id: paymentId,
    order_status: 'cancelled',
    payment_status: 'payment_review',
  }));
  state.setProviderOrder({
    ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0,
  });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'captured_payment_requires_manual_review');
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});

test('a cached idempotency response avoids provider and database side effects', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({
    claim_state: 'cached',
    run_id: null,
    claim_token: null,
    cached_response: { order_id: orderId, reconciliation_result: 'noncapture_unconfirmed' },
    cached_http_status: 200,
  }));
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'noncapture_unconfirmed');
  assert.equal(state.counts.order, 0);
  assert.equal(state.counts.collection, 0);
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 0);
});

test('a cached provider error stays idempotent and requires a new key for another lookup', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({
    claim_state: 'cached',
    run_id: null,
    claim_token: null,
    cached_response: {
      order_id: orderId,
      reconciliation_result: 'provider_lookup_unavailable',
      reservation_action: 'none',
      retryable: true,
      retry_with_new_idempotency_key: true,
    },
    cached_http_status: 503,
  }));
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(response.status, 503);
  assert.equal(body.retry_with_new_idempotency_key, true);
  assert.equal(state.counts.order, 0);
  assert.equal(state.counts.collection, 0);
  assert.equal(state.counts.finish, 0);
});

test('an active idempotency claim returns conflict without contacting provider', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({ claim_state: 'in_progress', run_id: null, claim_token: null }));
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  assert.equal(response.status, 409);
  assert.equal(state.counts.order, 0);
});

test('a wrong provider order identity is durably routed to review', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, id: 'order_other' });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'provider_evidence_incomplete');
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});

test('provider order amount mismatch cannot confirm capture or noncapture', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, amount: amount + 1 });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'provider_evidence_incomplete');
  assert.equal(state.counts.capture, 0);
});

test('provider order currency mismatch cannot confirm capture or noncapture', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, currency: 'USD' });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'provider_evidence_incomplete');
  assert.equal(state.counts.capture, 0);
});

test('an incomplete or mismatched payment collection remains held for review', async () => {
  const state = fixture();
  state.setCollection({ entity: 'collection', count: 2, items: [{ ...failedPayment }] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'provider_evidence_incomplete');
  assert.equal(state.counts.capture, 0);
});

test('oversized provider evidence is summarized and routed to review without capture', async () => {
  const state = fixture();
  const payments = Array.from({ length: 300 }, (_, index) => ({
    ...failedPayment,
    id: `pay_${String(index).padStart(4, '0')}_${'x'.repeat(256)}`,
  }));
  state.setProviderOrder({ ...defaultOrder, attempts: payments.length });
  state.setCollection({ entity: 'collection', count: payments.length, items: payments });
  let savedEvidence: Record<string, unknown> | null = null;
  const response = await handleRazorpayReconciliation(request(), {
    ...state.dependencies,
    finishDecision: async (input) => {
      savedEvidence = input.evidenceSummary;
      state.counts.finish++;
      return { response_payload: input.responsePayload, http_status: input.httpStatus };
    },
  });
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'provider_evidence_too_large');
  assert.equal(state.counts.capture, 0);
  assert.equal(savedEvidence?.truncated, true);
  assert.equal(
    (savedEvidence?.payment_collection as { returned_items: number }).returned_items,
    payments.length,
  );
});

test('a captured order with a current noncaptured payment snapshot is not accepted', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0 });
  state.setCollection({ entity: 'collection', count: 1, items: [{ ...capturedPayment }] });
  state.setDetail({ ...capturedPayment, status: 'authorized', captured: false });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.capture, 0);
});

test('captured amount mismatch from the provider is kept for review', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0 });
  state.setCollection({ entity: 'collection', count: 1, items: [{
    ...capturedPayment, amount_captured: amount - 1,
  }] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.payment, 0);
  assert.equal(state.counts.capture, 0);
});

test('provider lookup timeout is recorded as retryable and never releases inventory', async () => {
  const state = fixture({
    fetchProviderOrder: async () => { throw new Error('provider timeout'); },
  });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(response.status, 503);
  assert.equal(body.reconciliation_result, 'provider_lookup_unavailable');
  assert.equal(body.retryable, true);
  assert.equal(body.retry_with_new_idempotency_key, true);
  assert.equal(body.reservation_action, 'none');
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});

test('refund-bearing captures are kept for the existing review workflow', async () => {
  const state = fixture();
  state.setProviderOrder({ ...defaultOrder, status: 'paid', amount_paid: amount, amount_due: 0 });
  state.setCollection({ entity: 'collection', count: 1, items: [{
    ...capturedPayment, status: 'refunded', refund_status: 'full', amount_refunded: amount,
  }] });
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.capture, 0);
});

test('an attempt without a provider order is durably marked for manual review', async () => {
  const state = fixture();
  state.setClaim(defaultClaim({ provider_order_id: null }));
  const response = await handleRazorpayReconciliation(request(), state.dependencies);
  const body = await responseJson(response);
  assert.equal(body.reconciliation_result, 'manual_review');
  assert.equal(state.counts.order, 0);
  assert.equal(state.counts.capture, 0);
  assert.equal(state.counts.finish, 1);
});
