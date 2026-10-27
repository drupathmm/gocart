import { errorResponse, jsonResponse } from './cors.ts';
import {
  validateCapturedPayment,
  type RazorpayPayment,
} from './razorpay_payment_validation.ts';
import {
  assessRefundEvidence,
  capturedPaymentCollectionReviewCode,
  type PaymentCollection,
  type ProviderPayment,
  type ProviderOrder,
} from './razorpay_payment_collection_validation.ts';

type EventClaim = {
  claim_state: 'claimed' | 'processed' | 'busy' | 'conflict' | 'quarantined';
  lease_token: string | null;
};
type PaymentAttempt = {
  order_id: string;
  buyer_id: string;
  provider_order_id: string;
  expected_amount_paise: number | string;
  currency: string;
  state: string;
  provider_payment_id: string | null;
};

export type RazorpayWebhookDependencies = {
  configured: boolean;
  webhookSecret: string;
  claimEvent: (input: {
    eventId: string;
    eventType: string;
    providerEntityId: string | null;
  }) => Promise<EventClaim>;
  finishEvent: (input: {
    eventId: string;
    leaseToken: string;
    state: 'processed' | 'reconciliation_required' | 'failed';
    errorCode: string | null;
  }) => Promise<void>;
  loadAttemptByProviderOrder: (providerOrderId: string) => Promise<PaymentAttempt | null>;
  fetchProviderPayment: (paymentId: string) => Promise<ProviderPayment>;
  fetchProviderOrder: (providerOrderId: string) => Promise<ProviderOrder>;
  fetchProviderOrderPayments: (providerOrderId: string) => Promise<PaymentCollection>;
  recordVerifiedPayment: (input: {
    orderId: string;
    buyerId: string;
    providerOrderId: string;
    providerPaymentId: string;
    amountPaise: number;
    currency: string;
  }) => Promise<{ result?: string; error?: string }>;
  recordPaymentReview: (input: {
    orderId: string; buyerId: string; providerOrderId: string; providerPaymentId: string;
    amountPaise: number; currency: string; reason: string;
    reviewOutcome: 'capture_confirmed' | 'capture_unconfirmed' | 'capture_unknown';
  }) => Promise<{ result?: string; error?: string }>;
  recordRefundWebhook?: (input: {
    eventId: string;
    eventType: string;
    providerRefundId: string | null;
    paymentId: string | null;
    amountPaise: number | null;
    currency: string | null;
    receipt: string | null;
    providerStatus: string | null;
  }) => Promise<'recorded' | 'reconciliation_required'>;
};

type ParsedEvent = {
  eventType: string;
  paymentId: string | null;
  payloadOrderId: string | null;
  refundId: string | null;
  refundAmount: number | null;
  refundCurrency: string | null;
  refundReceipt: string | null;
  refundStatus: string | null;
};

function exceedsDatabaseTextLimit(value: string, maxCharacters: number): boolean {
  // PostgreSQL length(text) counts Unicode code points, not UTF-16 code units.
  return Array.from(value).length > maxCharacters;
}

function constantTimeHexEqual(expected: string, supplied: string): boolean {
  if (!/^[a-f0-9]{64}$/i.test(supplied)) return false;
  let mismatch = expected.length ^ supplied.length;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ (supplied.toLowerCase().charCodeAt(i) || 0);
  }
  return mismatch === 0;
}

async function verifyWebhookSignature(
  secret: string,
  rawBody: Uint8Array,
  supplied: string,
): Promise<boolean> {
  if (!/^[a-f0-9]{64}$/i.test(supplied)) return false;
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'HMAC', key, rawBody,
  );
  const expected = Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, '0')).join('');
  return constantTimeHexEqual(expected, supplied);
}

async function syntheticEventId(prefix: string, rawBody: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', rawBody);
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${prefix}:${hex}`;
}

async function readRawBody(req: Request, maxBytes: number): Promise<Uint8Array | null> {
  if (!req.body) return new Uint8Array();
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function parseEvent(body: unknown): ParsedEvent | null {
  const root = asRecord(body);
  if (!root || typeof root.event !== 'string' || root.event.length === 0) return null;
  const payload = asRecord(root.payload);
  const payment = asRecord(payload?.payment);
  const paymentEntity = asRecord(payment?.entity);
  const refund = asRecord(payload?.refund);
  const refundEntity = asRecord(refund?.entity);
  const order = asRecord(payload?.order);
  const orderEntity = asRecord(order?.entity);
  return {
    eventType: root.event,
    // Refund events carry their payment association on refund.entity.payment_id;
    // payment.entity is optional in those event payloads.
    paymentId: typeof paymentEntity?.id === 'string' && paymentEntity.id.length > 0
      ? paymentEntity.id
      : typeof refundEntity?.payment_id === 'string' && refundEntity.payment_id.length > 0
        ? refundEntity.payment_id
        : null,
    payloadOrderId: typeof paymentEntity?.order_id === 'string' && paymentEntity.order_id.length > 0
      ? paymentEntity.order_id
      : typeof orderEntity?.id === 'string' && orderEntity.id.length > 0
        ? orderEntity.id
        : null,
    refundId: typeof refundEntity?.id === 'string' && refundEntity.id.length > 0
      ? refundEntity.id : null,
    refundAmount: Number.isSafeInteger(refundEntity?.amount) && Number(refundEntity?.amount) > 0
      ? Number(refundEntity?.amount) : null,
    refundCurrency: typeof refundEntity?.currency === 'string' ? refundEntity.currency : null,
    refundReceipt: typeof refundEntity?.receipt === 'string' ? refundEntity.receipt : null,
    refundStatus: typeof refundEntity?.status === 'string' ? refundEntity.status : null,
  };
}

async function quarantineSignedDelivery(
  dependencies: RazorpayWebhookDependencies,
  input: {
    eventId: string;
    eventType: string;
    providerEntityId: string | null;
    errorCode: 'MALFORMED_SIGNED_BODY' | 'INVALID_EVENT_PAYLOAD' | 'MISSING_EVENT_ID'
      | 'INVALID_EVENT_ID' | 'UNSUPPORTED_EVENT_TYPE';
  },
): Promise<Response> {
  let claim: EventClaim;
  try {
    claim = await dependencies.claimEvent(input);
  } catch {
    return errorResponse(503, 'EVENT_CLAIM_UNAVAILABLE', 'Webhook event could not be durably quarantined.');
  }
  if (claim.claim_state === 'processed' || claim.claim_state === 'conflict'
      || claim.claim_state === 'quarantined') {
    return jsonResponse({ received: true, quarantined: true });
  }
  if (claim.claim_state === 'busy') {
    return errorResponse(503, 'EVENT_PROCESSING', 'Webhook event is still processing; retry later.');
  }
  if (claim.claim_state !== 'claimed' || !claim.lease_token) {
    return errorResponse(503, 'EVENT_CLAIM_INVALID', 'Webhook event claim was invalid.');
  }
  try {
    await dependencies.finishEvent({
      eventId: input.eventId,
      leaseToken: claim.lease_token,
      state: 'failed',
      errorCode: input.errorCode,
    });
    return jsonResponse({ received: true, quarantined: true });
  } catch {
    return errorResponse(503, 'EVENT_QUARANTINE_UNAVAILABLE', 'Webhook event quarantine needs retry.');
  }
}

export async function handleRazorpayWebhook(
  req: Request,
  dependencies: RazorpayWebhookDependencies,
): Promise<Response> {
  if (req.method !== 'POST') return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Use POST.');
  if (!dependencies.configured) {
    return errorResponse(500, 'WEBHOOK_NOT_CONFIGURED', 'Webhook processing is not configured.');
  }
  const rawLength = Number(req.headers.get('content-length') ?? '0');
  if (Number.isFinite(rawLength) && rawLength > 1_000_000) {
    return errorResponse(413, 'PAYLOAD_TOO_LARGE', 'Webhook payload is too large.');
  }

  let rawBody: Uint8Array | null;
  try {
    rawBody = await readRawBody(req, 1_000_000);
  } catch {
    return errorResponse(400, 'INVALID_BODY', 'Unable to read webhook payload.');
  }
  if (!rawBody) return errorResponse(413, 'PAYLOAD_TOO_LARGE', 'Webhook payload is too large.');
  const signature = req.headers.get('x-razorpay-signature') ?? '';
  try {
    if (!await verifyWebhookSignature(dependencies.webhookSecret, rawBody, signature)) {
      return errorResponse(401, 'INVALID_SIGNATURE', 'Webhook signature is invalid.');
    }
  } catch {
    return errorResponse(401, 'INVALID_SIGNATURE', 'Webhook signature is invalid.');
  }

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(rawBody));
  } catch {
    return await quarantineSignedDelivery(dependencies, {
      eventId: await syntheticEventId('malformed', rawBody),
      eventType: 'invalid.malformed_payload',
      providerEntityId: null,
      errorCode: 'MALFORMED_SIGNED_BODY',
    });
  }
  const event = parseEvent(body);
  const eventId = req.headers.get('x-razorpay-event-id')?.trim() ?? '';
  if (!event) {
    return await quarantineSignedDelivery(dependencies, {
      eventId: await syntheticEventId('invalid', rawBody),
      eventType: 'invalid.event_payload',
      providerEntityId: null,
      errorCode: 'INVALID_EVENT_PAYLOAD',
    });
  }
  const isRefundEvent = event.eventType.startsWith('refund.');
  const oversizedProviderIdentifier = [event.paymentId, event.payloadOrderId, event.refundId]
    .some((identifier) => identifier !== null && exceedsDatabaseTextLimit(identifier, 200));
  const missingPaymentIdentifiers = event.eventType.startsWith('payment.')
    && (!event.paymentId || !event.payloadOrderId);
  const unsupportedRefundEvent = isRefundEvent && ![
    'refund.created', 'refund.processed', 'refund.failed', 'refund.speed_changed',
  ].includes(event.eventType);
  if (exceedsDatabaseTextLimit(event.eventType, 200)
      || oversizedProviderIdentifier || missingPaymentIdentifiers || unsupportedRefundEvent) {
    // Never truncate signed input into a different event. Use only bounded,
    // server-generated metadata when recording malformed deliveries.
    return await quarantineSignedDelivery(dependencies, {
      eventId: await syntheticEventId('invalid-fields', rawBody),
      eventType: 'invalid.event_payload',
      providerEntityId: null,
      errorCode: unsupportedRefundEvent ? 'UNSUPPORTED_EVENT_TYPE' : 'INVALID_EVENT_PAYLOAD',
    });
  }
  if (!eventId) {
    return await quarantineSignedDelivery(dependencies, {
      eventId: await syntheticEventId('missing-id', rawBody),
      eventType: event.eventType,
      providerEntityId: event.paymentId ?? event.payloadOrderId,
      errorCode: 'MISSING_EVENT_ID',
    });
  }
  if (exceedsDatabaseTextLimit(eventId, 200)) {
    return await quarantineSignedDelivery(dependencies, {
      eventId: await syntheticEventId('invalid-id', rawBody),
      eventType: event.eventType,
      providerEntityId: event.paymentId ?? event.payloadOrderId,
      errorCode: 'INVALID_EVENT_ID',
    });
  }

  let claim: EventClaim;
  try {
    claim = await dependencies.claimEvent({
      eventId,
      eventType: event.eventType,
      providerEntityId: event.refundId ?? event.paymentId ?? event.payloadOrderId,
    });
  } catch {
    return errorResponse(503, 'EVENT_CLAIM_UNAVAILABLE', 'Webhook event could not be durably claimed.');
  }
  if (claim.claim_state === 'processed') return jsonResponse({ received: true, duplicate: true });
  if (claim.claim_state === 'conflict' || claim.claim_state === 'quarantined') {
    return jsonResponse({ received: true, quarantined: true });
  }
  if (claim.claim_state === 'busy') {
    return errorResponse(503, 'EVENT_PROCESSING', 'Webhook event is still processing; retry later.');
  }
  if (claim.claim_state !== 'claimed' || !claim.lease_token) {
    return errorResponse(503, 'EVENT_CLAIM_INVALID', 'Webhook event claim was invalid.');
  }

  const finish = async (
    state: 'processed' | 'reconciliation_required' | 'failed',
    errorCode: string | null = null,
  ) => await dependencies.finishEvent({ eventId, leaseToken: claim.lease_token!, state, errorCode });

  try {
    if (isRefundEvent) {
      if (!dependencies.recordRefundWebhook) {
        await finish('reconciliation_required', 'REFUND_HANDLER_UNAVAILABLE');
        return errorResponse(503, 'REFUND_HANDLER_UNAVAILABLE', 'Refund event needs reconciliation.');
      }
      const recorded = await dependencies.recordRefundWebhook({
        eventId,
        eventType: event.eventType,
        providerRefundId: event.refundId,
        paymentId: event.paymentId,
        amountPaise: event.refundAmount,
        currency: event.refundCurrency,
        receipt: event.refundReceipt,
        providerStatus: event.refundStatus,
      });
      if (recorded === 'reconciliation_required') {
        await finish('reconciliation_required', 'REFUND_EVENT_REQUIRES_RECONCILIATION');
        return jsonResponse({ received: true, reconciliation_required: true });
      }
      await finish('processed');
      return jsonResponse({ received: true, reconciled: true });
    }
    // Refund handling is not implemented in this stage. Keep unexpected event
    // families durably quarantined instead of silently acknowledging them.
    if (!event.eventType.startsWith('payment.')) {
      await finish('failed', 'UNSUPPORTED_EVENT_TYPE');
      return jsonResponse({ received: true, quarantined: true });
    }
    if (!event.paymentId || !event.payloadOrderId) {
      await finish('reconciliation_required', 'PAYMENT_ENTITY_MISSING');
      return errorResponse(503, 'PAYMENT_ENTITY_MISSING', 'Payment event needs reconciliation.');
    }

    const payment = await dependencies.fetchProviderPayment(event.paymentId);
    if (payment.id !== event.paymentId || payment.order_id !== event.payloadOrderId) {
      await finish('reconciliation_required', 'PROVIDER_ENTITY_MISMATCH');
      return errorResponse(503, 'PROVIDER_ENTITY_MISMATCH', 'Provider payment needs reconciliation.');
    }
    const attempt = await dependencies.loadAttemptByProviderOrder(payment.order_id as string);
    if (!attempt || attempt.provider_order_id !== payment.order_id) {
      await finish('reconciliation_required', 'LOCAL_ORDER_UNKNOWN');
      return errorResponse(503, 'LOCAL_ORDER_UNKNOWN', 'Payment does not map to a local order yet.');
    }

    const review = async (
      reason: string,
      reviewOutcome: 'capture_confirmed' | 'capture_unconfirmed' | 'capture_unknown' = 'capture_unknown',
    ): Promise<Response> => {
      const recorded = await dependencies.recordPaymentReview({
        orderId: attempt.order_id, buyerId: attempt.buyer_id, providerOrderId: attempt.provider_order_id,
        providerPaymentId: event.paymentId!, amountPaise: Number(attempt.expected_amount_paise),
        currency: attempt.currency, reason, reviewOutcome,
      });
      if (recorded.error) throw new Error('PAYMENT_REVIEW_UPDATE_FAILED');
      await finish('reconciliation_required', reason);
      return jsonResponse({ received: true, reconciliation_required: true });
    };
    const directRefund = assessRefundEvidence(payment);
    const captureIsConfirmed = payment.status === 'captured' && payment.captured === true
      && validateCapturedPayment(payment, {
        paymentId: event.paymentId,
        orderId: attempt.provider_order_id,
        amountPaise: Number(attempt.expected_amount_paise),
        currency: attempt.currency,
      }) === null;
    if (directRefund.malformed) return await review('PROVIDER_REFUND_DATA_INVALID',
      captureIsConfirmed ? 'capture_confirmed' : 'capture_unknown');
    if (directRefund.present) return await review('PROVIDER_REFUND_STATE_UNSUPPORTED',
      captureIsConfirmed ? 'capture_confirmed' : 'capture_unknown');

    if (payment.status === 'captured' || payment.captured === true) {
      const amountPaise = Number(attempt.expected_amount_paise);
      const validationCode = validateCapturedPayment(payment, {
        paymentId: event.paymentId,
        orderId: attempt.provider_order_id,
        amountPaise,
        currency: attempt.currency,
      });
      if (validationCode) {
        await finish('reconciliation_required', validationCode);
        return errorResponse(503, validationCode, 'Captured payment needs reconciliation.');
      }
      let siblingCode: string | null;
      try {
        const [providerOrder, collection] = await Promise.all([
          dependencies.fetchProviderOrder(attempt.provider_order_id),
          dependencies.fetchProviderOrderPayments(attempt.provider_order_id),
        ]);
        siblingCode = capturedPaymentCollectionReviewCode(collection,
          { paymentId: event.paymentId, orderId: attempt.provider_order_id, amountPaise,
            currency: attempt.currency, receipt: attempt.order_id }, providerOrder);
      } catch { siblingCode = 'PROVIDER_PAYMENT_LIST_UNAVAILABLE'; }
      if (siblingCode) return await review(siblingCode, 'capture_confirmed');
      const recordedReview = attempt.state === 'captured_review'
        && attempt.provider_payment_id === event.paymentId;
      if (!recordedReview) {
        const recorded = await dependencies.recordVerifiedPayment({
          orderId: attempt.order_id,
          buyerId: attempt.buyer_id,
          providerOrderId: attempt.provider_order_id,
          providerPaymentId: event.paymentId,
          amountPaise: payment.amount as number,
          currency: payment.currency as string,
        });
        if (recorded.error) {
          await finish('reconciliation_required', 'PAYMENT_STATE_UPDATE_FAILED');
          return errorResponse(503, 'PAYMENT_STATE_UPDATE_FAILED', 'Payment state needs reconciliation.');
        }
      }
    } else if (!(['created', 'authorized', 'failed'].includes(String(payment.status))
      && payment.captured === false)) {
      await finish('reconciliation_required', 'PROVIDER_STATE_UNRECOGNIZED');
      return errorResponse(503, 'PROVIDER_STATE_UNRECOGNIZED', 'Payment state needs reconciliation.');
    }

    await finish('processed');
    return jsonResponse({ received: true, reconciled: true });
  } catch {
    try {
      await finish('reconciliation_required', 'PROCESSING_INTERRUPTED');
    } catch {
      // If even this write fails, the database lease expires and allows retry.
    }
    return errorResponse(503, 'PROCESSING_INTERRUPTED', 'Webhook event needs retry.');
  }
}
