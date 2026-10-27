import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import type { RazorpayPayment } from './razorpay_payment_validation.ts';
import {
  handleVerifyPayment,
  type VerifyPaymentDependencies,
} from './verify_payment_handler.ts';

const secret = 'node-test-secret-only';
const buyerId = 'buyer-1';
const orderId = 'local-order-1';
const providerOrderId = 'rzp-order-1';
const paymentId = 'rzp-payment-1';
const amountPaise = 12500;

const captured: RazorpayPayment = {
  id: paymentId,
  order_id: providerOrderId,
  amount: amountPaise,
  currency: 'INR',
  status: 'captured',
  captured: true,
};

async function signatureFor(order: string, payment: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const digest = await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${order}|${payment}`),
  );
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function fixture(overrides: Partial<VerifyPaymentDependencies> = {}) {
  const {
    fetchProviderPayment: fetchProviderPaymentOverride,
    ...dependencyOverrides
  } = overrides;
  let paymentState = 'pending';
  let paymentStatus = 'unpaid';
  let recordCalls = 0;
  let providerCalls = 0;
  let captureEffects = 0;
  let verificationClaimCalls = 0;
  const cachedVerificationResponses = new Map<string, Record<string, unknown>>();
  const activeVerificationClaims = new Set<string>();
  const dependencies: VerifyPaymentDependencies = {
    configured: true,
    keySecret: secret,
    authenticate: async () => ({ id: buyerId }),
    loadOrder: async (id) => id === orderId ? {
      id,
      user_id: buyerId,
      status: paymentState,
      payment_status: paymentStatus,
      razorpay_order_id: providerOrderId,
    } : null,
    loadAttempt: async () => ({
      provider_order_id: providerOrderId,
      expected_amount_paise: amountPaise,
      currency: 'INR',
      state: paymentState === 'paid' ? 'captured' : 'created',
      provider_payment_id: paymentState === 'paid' ? paymentId : null,
    }),
    fetchProviderPayment: async (requestedPaymentId) => {
      providerCalls++;
      return fetchProviderPaymentOverride
        ? await fetchProviderPaymentOverride(requestedPaymentId)
        : captured;
    },
    fetchProviderOrder: async () => ({
      id: providerOrderId, receipt: orderId, amount: amountPaise, currency: 'INR', attempts: 1,
    }),
    fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 1, items: [{ ...captured, entity: 'payment' }] }),
    recordVerifiedPayment: async ({ providerPaymentId }) => {
      recordCalls++;
      if (paymentStatus === 'paid' && providerPaymentId === paymentId) {
        return { result: 'captured' };
      }
      captureEffects++;
      paymentState = 'paid';
      paymentStatus = 'paid';
      return { result: 'captured' };
    },
    recordPaymentReview: async () => ({ result: 'review_required' }),
    claimVerification: async ({ idempotencyKey }) => {
      verificationClaimCalls++;
      const cachedResponse = cachedVerificationResponses.get(idempotencyKey);
      if (cachedResponse) {
        return { claimState: 'cached', responsePayload: cachedResponse };
      }
      if (activeVerificationClaims.has(idempotencyKey)) return { claimState: 'in_progress' };
      activeVerificationClaims.add(idempotencyKey);
      return { claimState: 'claimed', claimToken: `local-verification-claim:${idempotencyKey}` };
    },
    cacheVerificationResponse: async ({ idempotencyKey, responsePayload }) => {
      cachedVerificationResponses.set(idempotencyKey, responsePayload);
      activeVerificationClaims.delete(idempotencyKey);
      return { responsePayload };
    },
    releaseVerificationClaim: async ({ idempotencyKey }) => {
      activeVerificationClaims.delete(idempotencyKey);
    },
    loadFinalOrder: async () => ({ status: paymentState, payment_status: paymentStatus }),
    ...dependencyOverrides,
  };
  return {
    dependencies,
    counts: () => ({ recordCalls, providerCalls }),
    captureEffects: () => captureEffects,
    verificationClaimCalls: () => verificationClaimCalls,
    paymentState: () => ({ status: paymentState, paymentStatus }),
  };
}

async function request(
  changes: Record<string, unknown> = {},
  authorization = 'Bearer local-test-token',
  idempotencyKey: string | null = 'verify-payment-idempotency-key',
) {
  const signature = await signatureFor(providerOrderId, paymentId);
  return new Request('http://localhost/verify-payment', {
    method: 'POST',
    headers: {
      ...(authorization ? { Authorization: authorization } : {}),
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      order_id: orderId,
      razorpay_order_id: providerOrderId,
      razorpay_payment_id: paymentId,
      razorpay_signature: signature,
      ...changes,
    }),
  });
}

async function responseBody(response: Response) {
  return await response.json() as { error?: { code?: string }; payment_status?: string };
}

test('valid authenticated verification records a captured payment', async () => {
  const state = fixture();
  const response = await handleVerifyPayment(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal((await responseBody(response)).payment_status, 'paid');
  assert.deepEqual(state.counts(), { recordCalls: 1, providerCalls: 1 });
});

test('verification requires an Idempotency-Key before provider access', async () => {
  const state = fixture();
  const response = await handleVerifyPayment(
    await request({}, 'Bearer local-test-token', null), state.dependencies,
  );
  assert.equal(response.status, 400);
  assert.equal((await responseBody(response)).error?.code, 'INVALID_IDEMPOTENCY_KEY');
  assert.deepEqual(state.counts(), { recordCalls: 0, providerCalls: 0 });
  assert.equal(state.verificationClaimCalls(), 0);
});

test('repeated verification returns the cached response without another provider call', async () => {
  const state = fixture();
  const first = await handleVerifyPayment(await request(), state.dependencies);
  const firstPayload = await responseBody(first);
  const second = await handleVerifyPayment(await request(), state.dependencies);
  const secondPayload = await responseBody(second);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.deepEqual(secondPayload, firstPayload);
  assert.deepEqual(state.counts(), { recordCalls: 1, providerCalls: 1 });
  assert.equal(state.captureEffects(), 1);
  assert.equal(state.verificationClaimCalls(), 2);
});

test('concurrent repeat verification is held by the active claim', async () => {
  let providerStarted!: () => void;
  const providerStartedPromise = new Promise<void>((resolve) => {
    providerStarted = resolve;
  });
  let finishProvider!: () => void;
  const providerGate = new Promise<void>((resolve) => {
    finishProvider = resolve;
  });
  const state = fixture({
    fetchProviderPayment: async () => {
      providerStarted();
      await providerGate;
      return captured;
    },
  });

  const firstPromise = handleVerifyPayment(await request(), state.dependencies);
  await providerStartedPromise;
  const duplicate = await handleVerifyPayment(await request(), state.dependencies);

  assert.equal(duplicate.status, 409);
  assert.equal((await responseBody(duplicate)).error?.code, 'IDEMPOTENCY_IN_PROGRESS');
  assert.deepEqual(state.counts(), { recordCalls: 0, providerCalls: 1 });

  finishProvider();
  const first = await firstPromise;
  assert.equal(first.status, 200);
  assert.deepEqual(state.counts(), { recordCalls: 1, providerCalls: 1 });
  assert.equal(state.captureEffects(), 1);
});

test('unauthenticated verification is rejected before database or provider access', async () => {
  const state = fixture();
  const response = await handleVerifyPayment(await request({}, ''), state.dependencies);
  assert.equal(response.status, 401);
  assert.deepEqual(state.counts(), { recordCalls: 0, providerCalls: 0 });
});

test('wrong buyer is rejected before provider access', async () => {
  const state = fixture({ authenticate: async () => ({ id: 'another-buyer' }) });
  const response = await handleVerifyPayment(await request(), state.dependencies);
  assert.equal(response.status, 403);
  assert.equal((await responseBody(response)).error?.code, 'NOT_AUTHORIZED');
  assert.deepEqual(state.counts(), { recordCalls: 0, providerCalls: 0 });
});

test('unknown local order is rejected before provider access', async () => {
  const state = fixture({ loadOrder: async () => null });
  const response = await handleVerifyPayment(await request(), state.dependencies);
  assert.equal(response.status, 404);
  assert.deepEqual(state.counts(), { recordCalls: 0, providerCalls: 0 });
});

test('wrong requested provider order is rejected before provider access', async () => {
  const state = fixture();
  const response = await handleVerifyPayment(
    await request({ razorpay_order_id: 'rzp-order-other' }), state.dependencies,
  );
  assert.equal((await responseBody(response)).error?.code, 'PROVIDER_ORDER_MISMATCH');
  assert.equal(state.counts().providerCalls, 0);
});

test('provider payment ID and order association must match', async (t) => {
  for (const [label, payment, expectedCode] of [
    ['payment ID', { ...captured, id: 'rzp-payment-other' }, 'PROVIDER_PAYMENT_MISMATCH'],
    ['provider order ID', { ...captured, order_id: 'rzp-order-other' }, 'PROVIDER_ORDER_MISMATCH'],
  ] as const) {
    await t.test(label, async () => {
      const state = fixture({ fetchProviderPayment: async () => payment });
      const response = await handleVerifyPayment(await request(), state.dependencies);
      assert.equal((await responseBody(response)).error?.code, expectedCode);
      assert.equal(state.counts().recordCalls, 0);
    });
  }
});

test('amount, currency, and captured status are required', async (t) => {
  for (const [label, payment, expectedCode] of [
    ['amount', { ...captured, amount: amountPaise - 1 }, 'PAYMENT_AMOUNT_MISMATCH'],
    ['currency', { ...captured, currency: 'USD' }, 'PAYMENT_CURRENCY_MISMATCH'],
    ['captured state', { ...captured, status: 'authorized', captured: false }, 'PAYMENT_NOT_CAPTURED'],
  ] as const) {
    await t.test(label, async () => {
      const state = fixture({ fetchProviderPayment: async () => payment });
      const response = await handleVerifyPayment(await request(), state.dependencies);
      assert.equal((await responseBody(response)).error?.code, expectedCode);
      assert.equal(state.counts().recordCalls, 0);
    });
  }
});

test('provider API failure leaves the order unpaid', async () => {
  const state = fixture({ fetchProviderPayment: async () => { throw new Error('offline'); } });
  const response = await handleVerifyPayment(await request(), state.dependencies);
  assert.equal(response.status, 502);
  assert.equal(state.paymentState().paymentStatus, 'unpaid');
  assert.equal(state.counts().recordCalls, 0);
});

test('database update failure after provider confirmation does not report paid', async () => {
  const state = fixture({ recordVerifiedPayment: async () => ({ error: 'database unavailable' }) });
  const response = await handleVerifyPayment(await request(), state.dependencies);
  assert.equal(response.status, 409);
  assert.equal(state.paymentState().paymentStatus, 'unpaid');
  assert.equal(state.counts().providerCalls, 1);
});

test('a different verification key cannot duplicate the captured payment effect', async () => {
  const state = fixture();
  const first = await handleVerifyPayment(
    await request({}, 'Bearer local-test-token', 'verify-capture-key-first'),
    state.dependencies,
  );
  const second = await handleVerifyPayment(
    await request({}, 'Bearer local-test-token', 'verify-capture-key-second'),
    state.dependencies,
  );
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal((await responseBody(second)).payment_status, 'paid');
  assert.deepEqual(state.counts(), { recordCalls: 2, providerCalls: 2 });
  assert.equal(state.captureEffects(), 1);
});

test('an active provider sibling is durably routed to review instead of paid', async () => {
  let reviewed = 0;
  const state = fixture({
    fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 2, items: [
      captured, { ...captured, id: 'rzp-payment-sibling', status: 'authorized', captured: false },
    ] }),
    recordPaymentReview: async () => { reviewed++; return { result: 'review_required' }; },
  });
  const response = await handleVerifyPayment(await request({}, 'Bearer local-test-token', 'verify-sibling-key'), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal((await responseBody(response)).verification_result, 'review_required');
  assert.equal(reviewed, 1);
  assert.equal(state.captureEffects(), 0);
});

test('an incomplete provider collection cannot promote a payment', async () => {
  let reviewed = 0;
  const state = fixture({
    fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 2, items: [captured] }),
    recordPaymentReview: async () => { reviewed++; return { result: 'review_required' }; },
  });
  const response = await handleVerifyPayment(await request({}, 'Bearer local-test-token', 'verify-incomplete-key'), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal((await responseBody(response)).verification_result, 'review_required');
  assert.equal(reviewed, 1);
  assert.equal(state.captureEffects(), 0);
});
