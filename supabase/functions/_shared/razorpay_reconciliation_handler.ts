import { validateCapturedPayment, type RazorpayPayment } from './razorpay_payment_validation.ts';
import {
  assessPaymentCollectionItems,
  assessRefundEvidence,
  paymentCollectionCompletenessCode,
} from './razorpay_payment_collection_validation.ts';

export type ProviderOrder = {
  id?: unknown;
  status?: unknown;
  amount?: unknown;
  amount_paid?: unknown;
  amount_due?: unknown;
  currency?: unknown;
  receipt?: unknown;
  attempts?: unknown;
};

export type ProviderPayment = RazorpayPayment & {
  entity?: unknown;
  refund_status?: unknown;
  amount_refunded?: unknown;
  amount_captured?: unknown;
};

export type PaymentCollection = {
  entity?: unknown;
  count?: unknown;
  items?: unknown;
};

export type ReconciliationClaim = {
  requested_order_id?: string;
  evidence_summary?: EvidenceSummary | null;
  claim_state: 'claimed' | 'cached' | 'in_progress' | 'conflict';
  run_id: string | null;
  claim_token: string | null;
  attempt_id: string | null;
  provider_order_id: string | null;
  expected_amount_paise: number | string | null;
  currency: string | null;
  order_status: string | null;
  payment_status: string | null;
  cached_response: unknown;
  cached_http_status: number | null;
  attempt_state: string | null;
  existing_provider_payment_id: string | null;
};

type ReconciliationFinal = {
  response_payload?: unknown;
  http_status?: number;
  error?: string;
};

export type EvidenceSummary = Record<string, unknown>;

export type RazorpayEvidenceContext = {
  orderId: string;
  providerOrderId: string;
  expectedAmountPaise: number;
  currency: string;
  attemptId: string | null;
  localOrderStatus: string | null;
  localPaymentStatus: string | null;
  localAttemptState: string | null;
  existingProviderPaymentId: string | null;
};

export type RazorpayReconciliationDependencies = {
  configured: boolean;
  serviceRoleKey: string;
  claim: (orderId: string, idempotencyKey: string) => Promise<{
    claim?: ReconciliationClaim;
    error?: string;
  }>;
  fetchProviderOrder: (providerOrderId: string) => Promise<ProviderOrder>;
  fetchProviderOrderPayments: (providerOrderId: string) => Promise<PaymentCollection>;
  fetchProviderPayment: (paymentId: string) => Promise<ProviderPayment>;
  finishDecision: (input: {
    runId: string;
    claimToken: string;
    decision: 'review_required' | 'noncapture_unconfirmed' | 'provider_error' | 'attempt_unavailable';
    providerOrderStatus: 'created' | 'attempted' | 'paid' | 'unknown' | null;
    providerAttemptCount: number | null;
    providerPaymentCount: number | null;
    evidenceSha256: string | null;
    evidenceSummary: EvidenceSummary | null;
    errorCode: string | null;
    httpStatus: number;
    responsePayload: Record<string, unknown>;
  }) => Promise<ReconciliationFinal>;
  recordCapturedPayment: (input: {
    runId: string;
    claimToken: string;
    providerPaymentId: string;
    amountPaise: number;
    currency: string;
    providerAttemptCount: number;
    providerPaymentCount: number;
    evidenceSha256: string;
    evidenceSummary: EvidenceSummary;
  }) => Promise<ReconciliationFinal>;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function error(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let mismatch = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) mismatch |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return mismatch === 0;
}

function statusForAudit(status: unknown): 'created' | 'attempted' | 'paid' | 'unknown' {
  return status === 'created' || status === 'attempted' || status === 'paid'
    ? status
    : 'unknown';
}

function safeCount(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : null;
}

async function readJsonBody(req: Request): Promise<
  { body: Record<string, unknown> | null; tooLarge: boolean }
> {
  if (!req.body) return { body: null, tooLarge: false };
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > 8192) {
      await reader.cancel();
      return { body: null, tooLarge: true };
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return { body: asRecord(JSON.parse(new TextDecoder().decode(bytes))), tooLarge: false };
  } catch {
    return { body: null, tooLarge: false };
  }
}

async function finalizeDecision(
  dependencies: RazorpayReconciliationDependencies,
  input: {
    claim: ReconciliationClaim;
    decision: 'review_required' | 'noncapture_unconfirmed' | 'provider_error' | 'attempt_unavailable';
    result: string;
    errorCode?: string | null;
    providerOrderStatus?: 'created' | 'attempted' | 'paid' | 'unknown' | null;
    providerAttemptCount?: number | null;
    providerPaymentCount?: number | null;
    evidenceSha256?: string | null;
    evidenceSummary?: EvidenceSummary | null;
    httpStatus?: number;
  },
): Promise<Response> {
  const { claim } = input;
  if (!claim.run_id || !claim.claim_token) {
    return error(503, 'RECONCILIATION_CLAIM_INVALID', 'Reconciliation could not be durably claimed.');
  }
  const payload = {
    reconciliation_result: input.result,
    reservation_action: 'none',
    retryable: input.httpStatus === 503,
    retry_with_new_idempotency_key: input.httpStatus === 503,
  };
  // The database function binds the response to this order's reconciliation run.
  const finalPayload = { ...payload, order_id: claim.requested_order_id };
  let result: ReconciliationFinal;
  try {
    result = await dependencies.finishDecision({
      runId: claim.run_id,
      claimToken: claim.claim_token,
      decision: input.decision,
      providerOrderStatus: input.providerOrderStatus ?? null,
      providerAttemptCount: input.providerAttemptCount ?? null,
      providerPaymentCount: input.providerPaymentCount ?? null,
      evidenceSha256: input.evidenceSha256 ?? null,
      evidenceSummary: input.evidenceSummary ?? claim.evidence_summary ?? null,
      errorCode: input.errorCode ?? null,
      httpStatus: input.httpStatus ?? 200,
      responsePayload: finalPayload,
    });
  } catch {
    result = { error: 'RECONCILIATION_RESULT_UNAVAILABLE' };
  }
  if (result.error || result.response_payload === null || result.response_payload === undefined) {
    return error(503, 'RECONCILIATION_RESULT_UNAVAILABLE', 'Reconciliation result could not be saved. Retry with the same key.');
  }
  return json(result.response_payload, result.http_status ?? input.httpStatus ?? 200);
}

function isPayment(value: unknown): value is ProviderPayment {
  const payment = asRecord(value);
  return payment !== null;
}

async function evidenceScalar(value: unknown): Promise<unknown> {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') {
    if (value.length <= 256) return value;
    const digest = await crypto.subtle.digest(
      'SHA-256', new TextEncoder().encode(value),
    );
    return {
      redacted_string: true,
      character_count: value.length,
      sha256: Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join(''),
    };
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : { invalid_type: 'non_finite_number' };
  }
  if (typeof value === 'boolean') return value;
  return { invalid_type: Array.isArray(value) ? 'array' : typeof value };
}

const evidenceScalarFields = [
  'entity', 'id', 'order_id', 'receipt', 'amount', 'amount_paid', 'amount_due',
  'currency', 'status', 'attempts', 'captured', 'refund_status', 'amount_refunded',
  'amount_captured',
] as const;

async function summarizeFields(value: unknown): Promise<Record<string, unknown>> {
  const record = asRecord(value);
  if (!record) return { malformed: true };
  const entries = await Promise.all(evidenceScalarFields
    .filter((field) => field in record)
    .map(async (field) => [field, await evidenceScalar(record[field])] as const));
  return Object.fromEntries(entries);
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(value);
}

export function normalizeRazorpayEvidence(
  order: ProviderOrder,
  collection: PaymentCollection,
  detail: ProviderPayment | null,
  context: RazorpayEvidenceContext,
): Promise<{ envelope: EvidenceSummary; summary: EvidenceSummary; oversized: boolean }> {
  return normalizeRazorpayEvidenceAsync(order, collection, detail, context);
}

async function normalizeRazorpayEvidenceAsync(
  order: ProviderOrder,
  collection: PaymentCollection,
  detail: ProviderPayment | null,
  context: RazorpayEvidenceContext,
): Promise<{ envelope: EvidenceSummary; summary: EvidenceSummary; oversized: boolean }> {
  const items = Array.isArray(collection.items) ? collection.items : null;
  const [orderSummary, normalizedPayments, detailSummary] = await Promise.all([
    summarizeFields(order),
    items ? Promise.all(items.map(summarizeFields)) : Promise.resolve(null),
    detail ? summarizeFields(detail) : Promise.resolve(null),
  ]);
  normalizedPayments?.sort((left, right) => {
    const leftJson = canonicalJson(left);
    const rightJson = canonicalJson(right);
    return leftJson < rightJson ? -1 : leftJson > rightJson ? 1 : 0;
  });
  const [collectionEntity, collectionCount, contextOrderId, contextProviderOrderId,
    contextAttemptId, localOrderStatus, localPaymentStatus, localAttemptState,
    existingProviderPaymentId] = await Promise.all([
    evidenceScalar(collection.entity),
    evidenceScalar(collection.count),
    evidenceScalar(context.orderId),
    evidenceScalar(context.providerOrderId),
    evidenceScalar(context.attemptId),
    evidenceScalar(context.localOrderStatus),
    evidenceScalar(context.localPaymentStatus),
    evidenceScalar(context.localAttemptState),
    evidenceScalar(context.existingProviderPaymentId),
  ]);
  const collectionSummary = {
    entity: collectionEntity,
    count: collectionCount,
    returned_items: items?.length ?? null,
    items_state: items !== null ? 'array'
      : !Object.prototype.hasOwnProperty.call(collection, 'items') ? 'missing'
      : collection.items === null ? 'null' : 'non_array',
    payments: normalizedPayments,
  };
  const envelope: EvidenceSummary = {
    schema_version: 2,
    reconciliation_context: {
      order_id: contextOrderId,
      expected_provider_order_id: contextProviderOrderId,
      expected_amount_paise: context.expectedAmountPaise,
      currency: context.currency,
      attempt_id: contextAttemptId,
      local_order_status: localOrderStatus,
      local_payment_status: localPaymentStatus,
      local_attempt_state: localAttemptState,
      existing_provider_payment_id: existingProviderPaymentId,
    },
    order: orderSummary,
    payment_collection: collectionSummary,
    payment_detail: detailSummary,
  };
  const encodedBytes = new TextEncoder().encode(canonicalJson(envelope)).byteLength;
  if (encodedBytes <= 32_768) return { envelope, summary: envelope, oversized: false };
  return {
    envelope,
    summary: {
      schema_version: 2,
      truncated: true,
      reconciliation_context: envelope.reconciliation_context,
      order: orderSummary,
      payment_collection: {
        entity: collectionSummary.entity,
        count: collectionSummary.count,
        returned_items: collectionSummary.returned_items,
        items_state: collectionSummary.items_state,
      },
      payment_detail: detailSummary,
    },
    oversized: true,
  };
}

export async function digestRazorpayEvidence(envelope: EvidenceSummary): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(canonicalJson(envelope)),
  );
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function buildProviderEvidence(
  order: ProviderOrder,
  collection: PaymentCollection,
  detail: ProviderPayment | null,
  context: RazorpayEvidenceContext,
): Promise<{ summary: EvidenceSummary; digest: string; oversized: boolean }> {
  const normalized = await normalizeRazorpayEvidence(order, collection, detail, context);
  return {
    summary: normalized.summary,
    digest: await digestRazorpayEvidence(normalized.envelope),
    oversized: normalized.oversized,
  };
}

export async function handleRazorpayReconciliation(
  req: Request,
  dependencies: RazorpayReconciliationDependencies,
): Promise<Response> {
  if (req.method !== 'POST') return error(405, 'METHOD_NOT_ALLOWED', 'Use POST.');
  if (!dependencies.configured || !dependencies.serviceRoleKey) {
    return error(503, 'RECONCILIATION_NOT_CONFIGURED', 'Payment reconciliation is unavailable.');
  }
  const suppliedAuthorization = req.headers.get('Authorization') ?? '';
  if (!constantTimeEqual(suppliedAuthorization, `Bearer ${dependencies.serviceRoleKey}`)) {
    return error(401, 'NOT_AUTHORIZED', 'A trusted server caller is required.');
  }
  const contentLength = Number(req.headers.get('content-length') ?? '0');
  if (Number.isFinite(contentLength) && contentLength > 8192) {
    return error(413, 'PAYLOAD_TOO_LARGE', 'Request body is too large.');
  }
  if (!req.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    return error(415, 'UNSUPPORTED_MEDIA_TYPE', 'Content-Type must be application/json.');
  }
  let parsed: { body: Record<string, unknown> | null; tooLarge: boolean };
  try {
    parsed = await readJsonBody(req);
  } catch {
    return error(400, 'INVALID_BODY', 'Request body must be valid JSON.');
  }
  if (parsed.tooLarge) return error(413, 'PAYLOAD_TOO_LARGE', 'Request body is too large.');
  const body = parsed.body;
  if (!body || Object.keys(body).some((key) => key !== 'order_id')) {
    return error(400, 'INVALID_BODY', 'Request body may contain only order_id.');
  }
  const orderId = typeof body?.order_id === 'string' ? body.order_id.trim() : '';
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(orderId)) {
    return error(400, 'INVALID_ORDER_ID', 'A valid order_id is required.');
  }
  const idempotencyKey = req.headers.get('Idempotency-Key')?.trim() ?? '';
  if (idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return error(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be between 8 and 128 characters.');
  }

  let claimed: { claim?: ReconciliationClaim; error?: string };
  try {
    claimed = await dependencies.claim(orderId, idempotencyKey);
  } catch {
    claimed = { error: 'CLAIM_UNAVAILABLE' };
  }
  if (claimed.error || !claimed.claim) {
    const code = claimed.error === 'ORDER_NOT_FOUND' ? 'ORDER_NOT_FOUND' : 'CLAIM_UNAVAILABLE';
    return error(code === 'ORDER_NOT_FOUND' ? 404 : 503, code,
      code === 'ORDER_NOT_FOUND' ? 'Order was not found.' : 'Reconciliation could not be claimed.');
  }
  const claim = { ...claimed.claim, requested_order_id: orderId };
  if (claim.claim_state === 'cached') {
    if (claim.cached_response !== null && typeof claim.cached_response === 'object'
        && !Array.isArray(claim.cached_response)) {
      return json(claim.cached_response, claim.cached_http_status ?? 200);
    }
    return error(503, 'INVALID_CACHED_RECONCILIATION', 'The saved reconciliation response is invalid.');
  }
  if (claim.claim_state === 'conflict') {
    return error(409, 'IDEMPOTENCY_CONFLICT', 'Idempotency-Key is already bound to another order.');
  }
  if (claim.claim_state === 'in_progress') {
    return error(409, 'RECONCILIATION_IN_PROGRESS', 'Reconciliation is already processing. Retry shortly with the same key.');
  }
  if (claim.claim_state !== 'claimed' || !claim.run_id || !claim.claim_token) {
    return error(503, 'RECONCILIATION_CLAIM_INVALID', 'Reconciliation could not be claimed.');
  }

  const attemptId = claim.attempt_id;
  const providerOrderId = claim.provider_order_id;
  const expectedAmount = Number(claim.expected_amount_paise);
  if (!attemptId || !providerOrderId || !Number.isSafeInteger(expectedAmount)
      || expectedAmount <= 0 || claim.currency !== 'INR') {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'attempt_unavailable',
      result: 'manual_review',
      errorCode: 'LOCAL_PAYMENT_ATTEMPT_INCOMPLETE',
    });
  }

  let providerOrder: ProviderOrder;
  let collection: PaymentCollection;
  try {
    // These are bounded read-only GETs. The adapter applies a 10 second timeout
    // to each; this handler performs no provider writes or automatic retries.
    [providerOrder, collection] = await Promise.all([
      dependencies.fetchProviderOrder(providerOrderId),
      dependencies.fetchProviderOrderPayments(providerOrderId),
    ]);
  } catch {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'provider_error',
      result: 'provider_lookup_unavailable',
      errorCode: 'PROVIDER_LOOKUP_FAILED',
      httpStatus: 503,
    });
  }

  const providerOrderStatus = statusForAudit(providerOrder.status);
  const providerAttemptCount = safeCount(providerOrder.attempts);
  const evidenceContext: RazorpayEvidenceContext = {
    orderId,
    providerOrderId,
    expectedAmountPaise: expectedAmount,
    currency: claim.currency,
    attemptId,
    localOrderStatus: claim.order_status,
    localPaymentStatus: claim.payment_status,
    localAttemptState: claim.attempt_state,
    existingProviderPaymentId: claim.existing_provider_payment_id,
  };
  const items = Array.isArray(collection.items) ? collection.items : null;
  const payments = items?.filter(isPayment) ?? [];
  const paymentCount = safeCount(collection.count);
  const hasCompleteCollection = paymentCollectionCompletenessCode(collection, providerAttemptCount) === null
    && items !== null && payments.length === items.length
    && paymentCount !== null;
  let evidence: { summary: EvidenceSummary; digest: string; oversized: boolean };
  try {
    evidence = await buildProviderEvidence(providerOrder, collection, null, evidenceContext);
  } catch {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'provider_error',
      result: 'provider_evidence_unavailable',
      errorCode: 'PROVIDER_EVIDENCE_DIGEST_FAILED',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      httpStatus: 503,
    });
  }
  if (evidence.oversized) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'provider_evidence_too_large',
      errorCode: 'PROVIDER_EVIDENCE_TOO_LARGE',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      evidenceSummary: evidence.summary,
    });
  }
  claim.evidence_summary = evidence.summary;

  const orderEvidenceError = providerOrder.id !== providerOrderId
      || providerOrder.receipt !== orderId
    ? 'PROVIDER_ORDER_MISMATCH'
    : providerOrder.amount !== expectedAmount
      ? 'PAYMENT_AMOUNT_MISMATCH'
      : providerOrder.currency !== claim.currency
        ? 'PAYMENT_CURRENCY_MISMATCH'
        : providerAttemptCount === null
          ? 'PROVIDER_ATTEMPT_COUNT_INVALID'
          : providerOrderStatus === 'unknown'
            ? 'PROVIDER_ORDER_STATUS_UNKNOWN'
            : null;
  const basicOrderMatches = orderEvidenceError === null;
  if (!basicOrderMatches || !hasCompleteCollection) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'provider_evidence_incomplete',
      errorCode: orderEvidenceError ?? 'PROVIDER_PAYMENT_LIST_INCOMPLETE',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      evidenceSummary: evidence.summary,
    });
  }

  const collectionAssessment = assessPaymentCollectionItems(collection, {
    orderId: providerOrderId, amountPaise: expectedAmount, currency: claim.currency,
  });
  const { malformedPayment, malformedRefund, refundEvidence, unresolvedSibling } = collectionAssessment;
  const capturedItems = collectionAssessment.capturedPayments;

  let detail: ProviderPayment | null = null;
  if (capturedItems.length === 1 && !malformedPayment && !malformedRefund
      && !refundEvidence && !unresolvedSibling) {
    try {
      detail = await dependencies.fetchProviderPayment(String(capturedItems[0].id));
    } catch {
      return await finalizeDecision(dependencies, {
        claim,
        decision: 'provider_error',
        result: 'captured_payment_lookup_unavailable',
        errorCode: 'PROVIDER_PAYMENT_LOOKUP_FAILED',
        providerOrderStatus,
        providerAttemptCount,
        providerPaymentCount: paymentCount,
        evidenceSha256: evidence.digest,
        evidenceSummary: evidence.summary,
      });
    }
  }
  try {
    evidence = await buildProviderEvidence(providerOrder, collection, detail, evidenceContext);
  } catch {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'provider_evidence_unavailable',
      errorCode: 'PROVIDER_EVIDENCE_DIGEST_FAILED',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
    });
  }
  if (evidence.oversized) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'provider_evidence_too_large',
      errorCode: 'PROVIDER_EVIDENCE_TOO_LARGE',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      evidenceSummary: evidence.summary,
    });
  }
  claim.evidence_summary = evidence.summary;

  const detailRefund = detail ? assessRefundEvidence(detail) : { present: false, malformed: false };
  if (refundEvidence || malformedRefund || malformedPayment || capturedItems.length > 1
      || (capturedItems.length > 0 && unresolvedSibling)
      || detailRefund.present || detailRefund.malformed) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'manual_review',
      errorCode: malformedRefund || detailRefund.malformed ? 'PROVIDER_REFUND_DATA_INVALID'
        : refundEvidence || detailRefund.present ? 'PROVIDER_REFUND_STATE_UNSUPPORTED'
        : capturedItems.length > 1 ? 'MULTIPLE_CAPTURED_PAYMENTS'
        : capturedItems.length > 0 && unresolvedSibling ? 'UNRESOLVED_SIBLING_PAYMENT'
        : 'PROVIDER_PAYMENT_MISMATCH',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      evidenceSummary: evidence.summary,
    });
  }

  if (capturedItems.length === 0) {
    const localCaptureState = claim.attempt_state === 'captured'
      || claim.attempt_state === 'captured_review'
      || claim.attempt_state === 'refund_pending'
      || claim.attempt_state === 'partially_refunded'
      || claim.attempt_state === 'refunded'
      || claim.attempt_state === 'refund_failed';
    if (localCaptureState) {
      return await finalizeDecision(dependencies, {
        claim,
        decision: 'review_required',
        result: 'local_payment_state_conflicts_with_provider_lookup',
        errorCode: 'LOCAL_PROVIDER_PAYMENT_STATE_MISMATCH',
        providerOrderStatus,
        providerAttemptCount,
        providerPaymentCount: paymentCount,
        evidenceSha256: evidence.digest,
      });
    }
    // Razorpay exposes no documented terminal noncapture order state in the
    // Orders API. Even a complete list of failed attempts does not close the
    // order against later attempts, so this result must not release inventory.
    return await finalizeDecision(dependencies, {
      claim,
      decision: providerOrderStatus === 'paid' ? 'review_required' : 'noncapture_unconfirmed',
      result: providerOrderStatus === 'paid' ? 'manual_review' : 'noncapture_unconfirmed',
      errorCode: providerOrderStatus === 'paid' ? 'PAID_ORDER_WITHOUT_CAPTURE_EVIDENCE' : null,
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
    });
  }

  if (providerOrderStatus !== 'paid'
      || providerOrder.amount_paid !== expectedAmount
      || providerOrder.amount_due !== 0
      || !detail
      || detail.entity !== 'payment'
      || (detail.amount_captured !== undefined && detail.amount_captured !== null
        && (typeof detail.amount_captured !== 'number'
          || !Number.isSafeInteger(detail.amount_captured)
          || detail.amount_captured !== expectedAmount))
      || detailRefund.present || detailRefund.malformed) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'manual_review',
      errorCode: 'CAPTURED_PAYMENT_ORDER_STATE_MISMATCH',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
    });
  }

  const paymentId = String(capturedItems[0].id);
  if (claim.attempt_state === 'captured_review'
      || (claim.attempt_state === 'captured'
        && claim.existing_provider_payment_id !== paymentId)) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'captured_payment_requires_manual_review',
      errorCode: claim.existing_provider_payment_id === paymentId
        ? null : 'PAYMENT_ALREADY_ASSOCIATED',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
    });
  }
  const stateCanReconcileCapture = claim.attempt_state === 'created'
    || claim.attempt_state === 'reconciliation_required'
    || claim.attempt_state === 'captured'
    || (claim.attempt_state === 'noncaptured'
      && claim.order_status === 'cancelled');
  if (!stateCanReconcileCapture) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'captured_payment_requires_manual_review',
      errorCode: 'PAYMENT_ATTEMPT_STATE_NOT_RECONCILABLE',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
    });
  }
  const validation = validateCapturedPayment(detail, {
    paymentId,
    orderId: providerOrderId,
    amountPaise: expectedAmount,
    currency: claim.currency,
  });
  if (validation) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'manual_review',
      errorCode: validation,
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
    });
  }

  let recorded: ReconciliationFinal;
  try {
    recorded = await dependencies.recordCapturedPayment({
      runId: claim.run_id,
      claimToken: claim.claim_token,
      providerPaymentId: paymentId,
      amountPaise: expectedAmount,
      currency: claim.currency,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      evidenceSummary: evidence.summary,
    });
  } catch {
    recorded = { error: 'CAPTURE_RECONCILIATION_FAILED' };
  }
  if (!recorded.response_payload || recorded.error) {
    return await finalizeDecision(dependencies, {
      claim,
      decision: 'review_required',
      result: 'verified_capture_requires_database_reconciliation',
      errorCode: 'PAYMENT_STATE_UPDATE_FAILED',
      providerOrderStatus,
      providerAttemptCount,
      providerPaymentCount: paymentCount,
      evidenceSha256: evidence.digest,
      httpStatus: 503,
    });
  }
  return json(recorded.response_payload, recorded.http_status ?? 200);
}
