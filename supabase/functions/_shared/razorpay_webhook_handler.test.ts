import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import type { RazorpayPayment } from './razorpay_payment_validation.ts';
import {
  handleRazorpayWebhook,
  type RazorpayWebhookDependencies,
} from './razorpay_webhook_handler.ts';

const secret = 'node-webhook-test-secret';
const paymentId = 'pay_test_1';
const providerOrderId = 'order_test_1';
const amountPaise = 4200;
type TestAttempt = {
  order_id: string;
  buyer_id: string;
  provider_order_id: string;
  expected_amount_paise: number;
  currency: string;
  state: string;
  provider_payment_id: string | null;
};
const captured: RazorpayPayment = {
  id: paymentId,
  order_id: providerOrderId,
  amount: amountPaise,
  currency: 'INR',
  status: 'captured',
  captured: true,
};

async function signatureFor(rawBody: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function body(event = 'payment.captured', payloadStatus = 'captured') {
  return JSON.stringify({
    event,
    payload: {
      payment: { entity: { id: paymentId, order_id: providerOrderId, status: payloadStatus } },
    },
  });
}

function fixture(overrides: Partial<RazorpayWebhookDependencies> = {}) {
  const eventStates = new Map<string, string>();
  const counts = { claim: 0, finish: [] as string[], provider: 0, record: 0 };
  let attempt: TestAttempt | null = {
    order_id: 'local-order-1',
    buyer_id: 'buyer-1',
    provider_order_id: providerOrderId,
    expected_amount_paise: amountPaise,
    currency: 'INR',
    state: 'created',
    provider_payment_id: null,
  };
  let dependencies: RazorpayWebhookDependencies = {
    configured: true,
    webhookSecret: secret,
    claimEvent: async ({ eventId }) => {
      counts.claim++;
      const state = eventStates.get(eventId);
      if (state === 'processed') return { claim_state: 'processed', lease_token: null };
      if (state === 'failed') return { claim_state: 'quarantined', lease_token: null };
      if (state === 'processing') return { claim_state: 'busy', lease_token: null };
      eventStates.set(eventId, 'processing');
      return { claim_state: 'claimed', lease_token: `lease-${counts.claim}` };
    },
    finishEvent: async ({ eventId, leaseToken, state }) => {
      assert.ok(leaseToken.startsWith('lease-'));
      counts.finish.push(state);
      eventStates.set(eventId, state);
    },
    loadAttemptByProviderOrder: async () => attempt,
    fetchProviderPayment: async () => {
      counts.provider++;
      return captured;
    },
    fetchProviderOrder: async () => ({
      id: providerOrderId, receipt: 'local-order-1', amount: amountPaise, currency: 'INR', attempts: 1,
    }),
    fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 1, items: [{ ...captured, entity: 'payment' }] }),
    recordVerifiedPayment: async () => {
      counts.record++;
      return { result: 'captured' };
    },
    recordPaymentReview: async () => ({ result: 'review_required' }),
  };
  dependencies = { ...dependencies, ...overrides };
  return {
    dependencies,
    counts,
    setAttempt(value: TestAttempt | null) { attempt = value; },
    setEventState(id: string, state: string) { eventStates.set(id, state); },
    eventState(id: string) { return eventStates.get(id); },
  };
}

async function request(
  rawBody = body(),
  signature?: string,
  eventId: string | null = 'evt_test_1',
) {
  return new Request('http://localhost/razorpay-webhook', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(eventId ? { 'x-razorpay-event-id': eventId } : {}),
      'x-razorpay-signature': signature ?? await signatureFor(rawBody),
    },
    body: rawBody,
  });
}

test('valid signature uses the exact raw bytes and records a captured payment', async () => {
  const state = fixture();
  const raw = '{\n "event":"payment.captured", "payload":{"payment":{"entity":{"id":"pay_test_1","order_id":"order_test_1"}}}\n}';
  const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
  assert.equal(response.status, 200);
  assert.deepEqual(state.counts, {
    claim: 1, finish: ['processed'], provider: 1, record: 1,
  });
});

test('invalid signature is rejected before event or provider access', async () => {
  const state = fixture();
  const validForOriginal = await signatureFor(body());
  const response = await handleRazorpayWebhook(await request(body(), '0'.repeat(64)), state.dependencies);
  const tampered = await handleRazorpayWebhook(
    await request(`${body()} `, validForOriginal, 'evt_tampered'), state.dependencies,
  );
  assert.equal(response.status, 401);
  assert.equal(tampered.status, 401);
  assert.deepEqual(state.counts, { claim: 0, finish: [], provider: 0, record: 0 });
});

test('signed malformed and missing-ID deliveries are durably quarantined', async (t) => {
  await t.test('malformed signed payload', async () => {
    const state = fixture();
    const raw = '{not-json';
    const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
    assert.equal(response.status, 200);
    assert.equal(state.counts.finish[0], 'failed');
    assert.equal(state.counts.provider, 0);
  });
  await t.test('missing Razorpay event ID and retry', async () => {
    const state = fixture();
    const raw = body();
    const first = await handleRazorpayWebhook(await request(raw, undefined, null), state.dependencies);
    const second = await handleRazorpayWebhook(await request(raw, undefined, null), state.dependencies);
    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(state.counts.claim, 2);
    assert.deepEqual(state.counts.finish, ['failed']);
    assert.equal(state.counts.provider, 0);
  });
});

test('oversized event type is quarantined with bounded server-generated metadata', async () => {
  let claimInput: { eventId: string; eventType: string; providerEntityId: string | null } | null = null;
  const state = fixture({
    claimEvent: async (input) => {
      claimInput = input;
      return { claim_state: 'claimed', lease_token: 'lease-oversized-type' };
    },
  });
  const raw = JSON.stringify({ event: 'x'.repeat(201), payload: {} });
  const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(claimInput?.eventType, 'invalid.event_payload');
  assert.equal(claimInput?.providerEntityId, null);
  assert.ok(claimInput?.eventId.startsWith('invalid-fields:'));
  assert.ok((claimInput?.eventId.length ?? 201) <= 200);
  assert.deepEqual(state.counts.finish, ['failed']);
  assert.equal(state.counts.provider, 0);
});

test('oversized event IDs and provider identifiers never reach constrained RPC fields', async (t) => {
  await t.test('oversized event ID uses a deterministic bounded key', async () => {
    let claimedId = '';
    const state = fixture({
      claimEvent: async ({ eventId }) => {
        claimedId = eventId;
        return { claim_state: 'claimed', lease_token: 'lease-oversized-id' };
      },
    });
    const raw = body();
    const response = await handleRazorpayWebhook(
      await request(raw, undefined, 'x'.repeat(201)), state.dependencies,
    );
    assert.equal(response.status, 200);
    assert.ok(claimedId.startsWith('invalid-id:'));
    assert.ok(claimedId.length <= 200);
    assert.deepEqual(state.counts.finish, ['failed']);
    assert.equal(state.counts.provider, 0);
  });

  for (const [name, entity] of [
    ['oversized payment ID', { id: 'p'.repeat(201), order_id: providerOrderId }],
    ['oversized provider order ID', { id: paymentId, order_id: 'o'.repeat(201) }],
  ] as const) {
    await t.test(name, async () => {
      let claimInput: { eventId: string; eventType: string; providerEntityId: string | null } | null = null;
      const state = fixture({
        claimEvent: async (input) => {
          claimInput = input;
          return { claim_state: 'claimed', lease_token: 'lease-oversized-provider-id' };
        },
      });
      const raw = JSON.stringify({
        event: 'payment.captured',
        payload: { payment: { entity } },
      });
      const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
      assert.equal(response.status, 200);
      assert.equal(claimInput?.eventType, 'invalid.event_payload');
      assert.equal(claimInput?.providerEntityId, null);
      assert.ok((claimInput?.eventId.length ?? 201) <= 200);
      assert.deepEqual(state.counts.finish, ['failed']);
      assert.equal(state.counts.provider, 0);
    });
  }
});

test('payment events with missing or malformed required identifiers are quarantined', async (t) => {
  const cases = [
    ['missing identifiers', { event: 'payment.captured', payload: { payment: { entity: {} } } }],
    ['malformed payment entity', { event: 'payment.captured', payload: { payment: { entity: 'not-an-object' } } }],
  ] as const;
  for (const [name, payload] of cases) {
    await t.test(name, async () => {
      const state = fixture();
      const raw = JSON.stringify(payload);
      const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
      assert.equal(response.status, 200);
      assert.deepEqual(state.counts.finish, ['failed']);
      assert.equal(state.counts.provider, 0);
      assert.equal(state.counts.record, 0);
    });
  }
});

test('text limits match PostgreSQL character counting for Unicode identifiers', async () => {
  let claimedEventType = '';
  const state = fixture({
    claimEvent: async ({ eventType }) => {
      claimedEventType = eventType;
      return { claim_state: 'claimed', lease_token: 'lease-unicode-event' };
    },
  });
  const eventType = '💳'.repeat(200);
  const raw = JSON.stringify({ event: eventType, payload: {} });
  const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(claimedEventType, eventType);
  assert.deepEqual(state.counts.finish, ['failed']);
});

test('repeated delivery of the same signed malformed body stays quarantined', async () => {
  const state = fixture();
  const raw = JSON.stringify({ event: 'z'.repeat(201), payload: {} });
  const first = await handleRazorpayWebhook(await request(raw), state.dependencies);
  const second = await handleRazorpayWebhook(await request(raw), state.dependencies);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(state.counts.claim, 2);
  assert.deepEqual(state.counts.finish, ['failed']);
  assert.equal(state.counts.provider, 0);
});

test('quarantine claim or finish RPC failures remain retryable', async (t) => {
  const raw = JSON.stringify({ event: 'payment.captured', payload: { payment: { entity: {} } } });
  await t.test('claim RPC failure', async () => {
    const state = fixture({ claimEvent: async () => { throw new Error('database unavailable'); } });
    const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
    assert.equal(response.status, 503);
    assert.equal((await response.json() as { error?: { code?: string } }).error?.code,
      'EVENT_CLAIM_UNAVAILABLE');
    assert.equal(state.counts.provider, 0);
  });
  await t.test('finish RPC failure', async () => {
    const state = fixture({ finishEvent: async () => { throw new Error('database unavailable'); } });
    const response = await handleRazorpayWebhook(await request(raw), state.dependencies);
    assert.equal(response.status, 503);
    assert.equal((await response.json() as { error?: { code?: string } }).error?.code,
      'EVENT_QUARANTINE_UNAVAILABLE');
    assert.equal(state.counts.provider, 0);
  });
});

test('invalid signature with malformed content is rejected before quarantine RPCs', async () => {
  const state = fixture();
  const response = await handleRazorpayWebhook(
    await request('{not-json', '0'.repeat(64), 'evt_invalid_malformed_signature'),
    state.dependencies,
  );
  assert.equal(response.status, 401);
  assert.deepEqual(state.counts, { claim: 0, finish: [], provider: 0, record: 0 });
});

test('event ID metadata conflict is durably quarantined without provider access', async () => {
  const state = fixture({ claimEvent: async () => ({ claim_state: 'conflict', lease_token: null }) });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal((await response.json() as { quarantined?: boolean }).quarantined, true);
  assert.equal(state.counts.provider, 0);
});

test('refund events without a configured refund recorder remain retryable', async (t) => {
  await t.test('refund event family', async () => {
    const state = fixture();
    const response = await handleRazorpayWebhook(
      await request(body('refund.processed'), undefined, 'evt_refund_event'), state.dependencies,
    );
    assert.equal(response.status, 503);
    assert.deepEqual(state.counts.finish, ['reconciliation_required']);
    assert.equal(state.counts.provider, 0);
  });
  await t.test('provider reports a refund on a payment event', async () => {
    const state = fixture({ fetchProviderPayment: async () => ({
      ...captured,
      status: 'refunded',
      refund_status: 'full',
      amount_refunded: amountPaise,
    }) });
    const response = await handleRazorpayWebhook(await request(), state.dependencies);
    assert.equal(response.status, 200);
    assert.deepEqual(state.counts.finish, ['reconciliation_required']);
    assert.equal(state.counts.record, 0);
  });
});

test('documented refund payload is passed to durable reconciliation with its payment association', async () => {
  let received: Record<string, unknown> | null = null;
  const state = fixture({
    recordRefundWebhook: async (input) => {
      received = input;
      return 'recorded';
    },
  });
  const raw = JSON.stringify({
    event: 'refund.processed',
    payload: { refund: { entity: {
      id: 'rfnd_test_1', payment_id: paymentId, amount: amountPaise,
      currency: 'INR', receipt: 'gcr_test_1', status: 'processed',
    } } },
  });
  const response = await handleRazorpayWebhook(
    await request(raw, undefined, 'evt_refund_processed'), state.dependencies,
  );
  assert.equal(response.status, 200);
  assert.equal(received?.providerRefundId, 'rfnd_test_1');
  assert.equal(received?.paymentId, paymentId);
  assert.equal(received?.amountPaise, amountPaise);
  assert.deepEqual(state.counts.finish, ['processed']);
});

test('duplicate refund delivery is deduplicated before a second recorder call', async () => {
  let records = 0;
  const state = fixture({
    recordRefundWebhook: async () => { records++; return 'recorded'; },
  });
  const raw = JSON.stringify({ event: 'refund.processed', payload: { refund: { entity: {
    id: 'rfnd_test_duplicate', payment_id: paymentId, amount: amountPaise,
    currency: 'INR', status: 'processed',
  } } } });
  const first = await handleRazorpayWebhook(
    await request(raw, undefined, 'evt_refund_duplicate'), state.dependencies,
  );
  const duplicate = await handleRazorpayWebhook(
    await request(raw, undefined, 'evt_refund_duplicate'), state.dependencies,
  );
  assert.equal(first.status, 200);
  assert.equal(duplicate.status, 200);
  assert.equal(records, 1);
});

test('incomplete refund payload is sent to durable reconciliation rather than inferred', async () => {
  let received: Record<string, unknown> | null = null;
  const state = fixture({ recordRefundWebhook: async (input) => {
    received = input;
    return 'reconciliation_required';
  } });
  const raw = JSON.stringify({
    event: 'refund.created', payload: { refund: { entity: { id: 'rfnd_incomplete' } } },
  });
  const response = await handleRazorpayWebhook(
    await request(raw, undefined, 'evt_refund_incomplete'), state.dependencies,
  );
  assert.equal(response.status, 200);
  assert.equal(received?.providerRefundId, 'rfnd_incomplete');
  assert.equal(received?.paymentId, null);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
});

test('out-of-order refund event is left to durable conflict reconciliation', async () => {
  const state = fixture({ recordRefundWebhook: async ({ eventType }) =>
    eventType === 'refund.created' ? 'reconciliation_required' : 'recorded' });
  const payload = (status: string) => JSON.stringify({
    event: status === 'processed' ? 'refund.processed' : 'refund.created',
    payload: { refund: { entity: {
      id: 'rfnd_out_of_order', payment_id: paymentId, amount: amountPaise,
      currency: 'INR', status,
    } } },
  });
  const terminal = await handleRazorpayWebhook(
    await request(payload('processed'), undefined, 'evt_refund_terminal'), state.dependencies,
  );
  const stale = await handleRazorpayWebhook(
    await request(payload('pending'), undefined, 'evt_refund_stale'), state.dependencies,
  );
  assert.equal(terminal.status, 200);
  assert.equal(stale.status, 200);
  assert.deepEqual(state.counts.finish, ['processed', 'reconciliation_required']);
});

test('already processed event is acknowledged without repeating provider work', async () => {
  const state = fixture({ claimEvent: async () => ({ claim_state: 'processed', lease_token: null }) });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(state.counts.provider, 0);
  assert.equal(state.counts.record, 0);
});

test('duplicate delivery during an active lease is retryable', async () => {
  const state = fixture({ claimEvent: async () => ({ claim_state: 'busy', lease_token: null }) });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.equal(state.counts.provider, 0);
});

test('out-of-order authorized snapshot reconciles current captured provider state', async () => {
  const state = fixture({ fetchProviderPayment: async () => ({ ...captured }) });
  const response = await handleRazorpayWebhook(
    await request(body('payment.authorized', 'authorized'), undefined, 'evt_authorized_old'), state.dependencies,
  );
  assert.equal(response.status, 200);
  assert.equal(state.counts.record, 1);
});

test('unknown provider order is durable and left for reconciliation', async () => {
  const state = fixture({ loadAttemptByProviderOrder: async () => null });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
  assert.equal(state.counts.record, 0);
});

test('provider payment ID or order mismatch never reaches the verified-payment RPC', async (t) => {
  for (const [name, providerPayment] of [
    ['payment ID', { ...captured, id: 'pay_other' }],
    ['order ID', { ...captured, order_id: 'order_other' }],
  ] as const) {
    await t.test(name, async () => {
      const state = fixture({ fetchProviderPayment: async () => providerPayment });
      const response = await handleRazorpayWebhook(await request(), state.dependencies);
      assert.equal(response.status, 503);
      assert.equal(state.counts.record, 0);
      assert.deepEqual(state.counts.finish, ['reconciliation_required']);
    });
  }
});

test('amount, currency, and capture mismatches are not recorded', async (t) => {
  for (const [name, providerPayment] of [
    ['amount', { ...captured, amount: amountPaise + 1 }],
    ['currency', { ...captured, currency: 'USD' }],
    ['not captured', { ...captured, status: 'authorized', captured: false }],
  ] as const) {
    await t.test(name, async () => {
      const state = fixture({ fetchProviderPayment: async () => providerPayment });
      const response = await handleRazorpayWebhook(await request(), state.dependencies);
      assert.equal(response.status, name === 'not captured' ? 200 : 503);
      assert.equal(state.counts.record, 0);
    });
  }
});

test('unknown provider payment is retriable and remains unmodified', async () => {
  const state = fixture({ fetchProviderPayment: async () => { throw new Error('not found'); } });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
  assert.equal(state.counts.record, 0);
});

test('provider API timeout remains retryable and does not mark the order paid', async () => {
  const state = fixture({
    fetchProviderPayment: async () => {
      throw new DOMException('Provider request timed out.', 'TimeoutError');
    },
  });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
  assert.equal(state.counts.record, 0);
});

test('webhook claim RPC failure requests provider retry before external access', async () => {
  const state = fixture({
    claimEvent: async () => { throw new Error('simulated RPC failure'); },
  });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.equal((await response.json() as { error?: { code?: string } }).error?.code,
    'EVENT_CLAIM_UNAVAILABLE');
  assert.equal(state.counts.provider, 0);
  assert.equal(state.counts.record, 0);
});

test('unknown local order is retriable and remains unmodified', async () => {
  const state = fixture({ loadAttemptByProviderOrder: async () => null });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
  assert.equal(state.counts.record, 0);
});

test('database failure records retry state and a later delivery can reconcile', async () => {
  let failOnce = true;
  const state = fixture({
    recordVerifiedPayment: async () => {
      state.counts.record++;
      if (failOnce) {
        failOnce = false;
        return { error: 'temporary database failure' };
      }
      return { result: 'captured' };
    },
  });
  const first = await handleRazorpayWebhook(await request(), state.dependencies);
  const second = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(first.status, 503);
  assert.equal(second.status, 200);
  assert.deepEqual(state.counts.finish, ['reconciliation_required', 'processed']);
  assert.equal(state.counts.record, 2);
});

test('captured payment racing cancellation is delegated to the database review transition', async () => {
  const state = fixture({ recordVerifiedPayment: async () => {
    state.counts.record++;
    return { result: 'review_required' };
  } });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(state.counts.record, 1);
  assert.equal(state.eventState('evt_test_1'), 'processed');
});

test('retry after payment-review mutation completes without reapplying the transition', async () => {
  const state = fixture();
  let completionFailsOnce = true;
  state.dependencies.finishEvent = async ({ eventId, leaseToken, state: nextState }) => {
    assert.ok(leaseToken.startsWith('lease-'));
    state.counts.finish.push(nextState);
    if (nextState === 'processed' && completionFailsOnce) {
      completionFailsOnce = false;
      throw new Error('simulated completion timeout');
    }
    state.setEventState(eventId, nextState);
  };
  state.dependencies.recordVerifiedPayment = async () => {
    state.counts.record++;
    state.setAttempt({
      order_id: 'local-order-1',
      buyer_id: 'buyer-1',
      provider_order_id: providerOrderId,
      expected_amount_paise: amountPaise,
      currency: 'INR',
      state: 'captured_review',
      provider_payment_id: paymentId,
    });
    return { result: 'review_required' };
  };

  const first = await handleRazorpayWebhook(await request(), state.dependencies);
  const second = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(first.status, 503);
  assert.equal(second.status, 200);
  assert.equal(state.counts.record, 1);
  assert.deepEqual(state.counts.finish, [
    'processed', 'reconciliation_required', 'processed',
  ]);
  assert.equal(state.eventState('evt_test_1'), 'processed');
});

test('ordinary request metadata cannot set payment state without valid provider reconciliation', async () => {
  const state = fixture({ fetchProviderPayment: async () => ({ ...captured, status: 'authorized' }) });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 503);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
  assert.equal(state.counts.record, 0);
});

test('webhook capture with an active sibling is routed to durable review', async () => {
  let reviewed = 0;
  let outcome = '';
  const state = fixture({
    fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 2, items: [
      captured, { ...captured, id: 'pay_sibling', status: 'authorized', captured: false },
    ] }),
    recordPaymentReview: async (input) => { reviewed++; outcome = input.reviewOutcome; return { result: 'review_required' }; },
  });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(reviewed, 1);
  assert.equal(outcome, 'capture_confirmed');
  assert.equal(state.counts.record, 0);
  assert.deepEqual(state.counts.finish, ['reconciliation_required']);
});

for (const [name, patch] of [
  ['valid zero refund', { refund_status: null, amount_refunded: 0 }],
  ['positive refund', { refund_status: 'partial', amount_refunded: 1 }],
  ['negative refund', { refund_status: 'partial', amount_refunded: -1 }],
  ['string refund', { refund_status: 'partial', amount_refunded: '1' }],
  ['wrong refund status type', { refund_status: true, amount_refunded: 0 }],
] as const) {
  test(`webhook ${name} metadata is not silently accepted`, async () => {
    let reviewed = 0;
    let outcome = '';
    const state = fixture({
      fetchProviderPayment: async () => ({ ...captured, ...patch }),
      fetchProviderOrderPayments: async () => ({ entity: 'collection', count: 1, items: [{ ...captured, entity: 'payment', ...patch }] }),
      recordPaymentReview: async (input) => { reviewed++; outcome = input.reviewOutcome; return { result: 'review_required' }; },
    });
    const response = await handleRazorpayWebhook(await request(), state.dependencies);
    if (name === 'valid zero refund') assert.equal(state.counts.record, 1);
    else {
      assert.equal(response.status, 200);
      assert.equal(reviewed, 1);
      assert.equal(outcome, 'capture_confirmed');
      assert.equal(state.counts.record, 0);
    }
  });
}

test('a refund-bearing non-captured payment is reviewed without capture classification', async () => {
  let outcome = '';
  const state = fixture({
    fetchProviderPayment: async () => ({ ...captured, status: 'authorized', captured: false,
      refund_status: 'partial', amount_refunded: 1 }),
    recordPaymentReview: async (input) => { outcome = input.reviewOutcome; return { result: 'review_required' }; },
  });
  const response = await handleRazorpayWebhook(await request(), state.dependencies);
  assert.equal(response.status, 200);
  assert.equal(outcome, 'capture_unknown');
  assert.equal(state.counts.record, 0);
});
