export type RefundRequestSnapshot = Readonly<{
  refundId: string;
  paymentId: string;
  amountPaise: number;
  currency: string;
  speed: 'normal' | 'optimum';
  receipt: string;
  idempotencyKey: string;
  approvalReference: string | null;
  knownProviderRefundId: string | null;
}>;

export type RefundClaim =
  | { state: 'claimed'; leaseToken: string; request: RefundRequestSnapshot }
  | { state: 'busy' | 'approval_required' | 'reconciliation_required' | 'terminal' };

export type ProviderRefund = {
  id?: unknown;
  payment_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  receipt?: unknown;
  status?: unknown;
};

export type RefundRequestBody = Readonly<{
  amount: number;
  speed: 'normal' | 'optimum';
  receipt: string;
}>;

export interface MockableRazorpayRefundProvider {
  createRefund(input: {
    paymentId: string;
    idempotencyKey: string;
    body: RefundRequestBody;
  }): Promise<{ httpStatus: number; body?: unknown }>;
  listRefunds(paymentId: string): Promise<readonly ProviderRefund[]>;
  fetchRefund(paymentId: string, refundId: string): Promise<ProviderRefund>;
}

export interface RefundDispatchStore {
  claim(refundId: string): Promise<RefundClaim>;
  recordValidatedResult(input: {
    refundId: string;
    leaseToken: string;
    providerRefundId: string;
    providerStatus: 'pending' | 'processed' | 'failed';
    paymentId: string;
    amountPaise: number;
    currency: string;
    receipt: string | null;
  }): Promise<void>;
  markUnknown(input: {
    refundId: string;
    leaseToken: string;
    reason: string;
  }): Promise<void>;
  recordReconciliation(input: {
    refundId: string;
    reason: string;
    candidateRefundIds: readonly string[];
  }): Promise<void>;
}

export type DispatchOutcome =
  | { state: 'approval_required' | 'busy' | 'terminal' | 'reconciliation_required' }
  | { state: 'submitted'; providerStatus: 'pending' | 'processed' | 'failed' }
  | { state: 'unknown'; reason: string }
  | { state: 'result_write_failed'; reason: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function validateRefundResponse(
  raw: unknown,
  request: RefundRequestSnapshot,
): { ok: true; value: Required<Pick<ProviderRefund,
  'id' | 'payment_id' | 'amount' | 'currency' | 'status'>> & { receipt: string | null } }
  | { ok: false; reason: string } {
  if (!isRecord(raw)) return { ok: false, reason: 'MALFORMED_PROVIDER_RESPONSE' };
  const id = raw.id;
  const paymentId = raw.payment_id;
  const amount = raw.amount;
  const currency = raw.currency;
  const status = raw.status;
  const receipt = raw.receipt;
  if (typeof id !== 'string' || id.trim().length === 0) {
    return { ok: false, reason: 'PROVIDER_REFUND_ID_MISSING' };
  }
  if (paymentId !== request.paymentId) return { ok: false, reason: 'PROVIDER_PAYMENT_MISMATCH' };
  if (!Number.isSafeInteger(amount) || amount !== request.amountPaise) {
    return { ok: false, reason: 'PROVIDER_AMOUNT_MISMATCH' };
  }
  if (currency !== request.currency) return { ok: false, reason: 'PROVIDER_CURRENCY_MISMATCH' };
  if (receipt !== null && receipt !== undefined && receipt !== request.receipt) {
    return { ok: false, reason: 'PROVIDER_RECEIPT_MISMATCH' };
  }
  if (!['pending', 'processed', 'failed'].includes(String(status))) {
    return { ok: false, reason: 'UNSUPPORTED_PROVIDER_REFUND_STATUS' };
  }
  return {
    ok: true,
    value: {
      id,
      payment_id: paymentId,
      amount,
      currency,
      status,
      receipt: typeof receipt === 'string' ? receipt : null,
    },
  };
}

function requestBody(request: RefundRequestSnapshot): RefundRequestBody {
  return Object.freeze({
    amount: request.amountPaise,
    speed: request.speed,
    receipt: request.receipt,
  });
}

/**
 * Server-side orchestration only. This module has no live provider adapter;
 * callers must inject one. Approval is checked durably by store.claim, and
 * every retry uses the immutable persisted body and the same header key.
 */
export async function dispatchApprovedRefund(
  refundId: string,
  store: RefundDispatchStore,
  provider: MockableRazorpayRefundProvider,
): Promise<DispatchOutcome> {
  const claim = await store.claim(refundId);
  if (claim.state !== 'claimed') {
    return { state: claim.state };
  }
  const { request, leaseToken } = claim;
  if (!request.approvalReference) return { state: 'approval_required' };

  if (request.knownProviderRefundId) {
    try {
      const known = await provider.fetchRefund(request.paymentId, request.knownProviderRefundId);
      return await recordProviderResult(store, request, leaseToken, known);
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'KNOWN_REFUND_LOOKUP_FAILED');
    }
  }

  const body = requestBody(request);
  let response: { httpStatus: number; body?: unknown };
  try {
    response = await provider.createRefund({
      paymentId: request.paymentId,
      idempotencyKey: request.idempotencyKey,
      body,
    });
  } catch {
    return await markUnknown(store, request.refundId, leaseToken, 'PROVIDER_REQUEST_OUTCOME_UNKNOWN');
  }

  if (response.httpStatus === 409) {
    // Listing is diagnostic only: receipt/amount/time do not prove which
    // operation created a refund. Leave the intent reserved and retry later
    // with the same header key and byte-equivalent body.
    let candidates: readonly ProviderRefund[] = [];
    try {
      candidates = await provider.listRefunds(request.paymentId);
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'IDEMPOTENCY_CONFLICT_LOOKUP_FAILED');
    }
    const candidateIds = candidates.filter((candidate) =>
      candidate.payment_id === request.paymentId
        && candidate.amount === request.amountPaise
        && candidate.currency === request.currency
        && candidate.receipt === request.receipt
        && typeof candidate.id === 'string'
    ).map((candidate) => String(candidate.id));
    try {
      await store.recordReconciliation({
        refundId: request.refundId,
        reason: candidateIds.length > 0
          ? 'IDEMPOTENCY_CONFLICT_MATCHING_REFUND_NEEDS_PROVIDER_IDEMPOTENCY_REPLAY'
          : 'IDEMPOTENCY_CONFLICT_NO_UNAMBIGUOUS_REFUND_MATCH',
        candidateRefundIds: candidateIds,
      });
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'RECONCILIATION_WRITE_FAILED');
    }
    return await markUnknown(store, request.refundId, leaseToken, 'PROVIDER_IDEMPOTENCY_CONFLICT');
  }

  if (response.httpStatus < 200 || response.httpStatus >= 300) {
    return await markUnknown(store, request.refundId, leaseToken, `PROVIDER_HTTP_${response.httpStatus}`);
  }
  const validated = validateRefundResponse(response.body, request);
  if (!validated.ok) {
    try {
      await store.recordReconciliation({
        refundId: request.refundId,
        reason: validated.reason,
        candidateRefundIds: [],
      });
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'RECONCILIATION_WRITE_FAILED');
    }
    return await markUnknown(store, request.refundId, leaseToken, validated.reason);
  }
  if (request.knownProviderRefundId
      && request.knownProviderRefundId !== validated.value.id) {
    try {
      await store.recordReconciliation({
        refundId: request.refundId,
        reason: 'PROVIDER_REFUND_ID_CONFLICT',
        candidateRefundIds: [validated.value.id],
      });
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'RECONCILIATION_WRITE_FAILED');
    }
    return await markUnknown(store, request.refundId, leaseToken, 'PROVIDER_REFUND_ID_CONFLICT');
  }

  return await writeResult(store, request, leaseToken, validated.value);
}

async function recordProviderResult(
  store: RefundDispatchStore,
  request: RefundRequestSnapshot,
  leaseToken: string,
  providerResponse: unknown,
): Promise<DispatchOutcome> {
  const validated = validateRefundResponse(providerResponse, request);
  if (!validated.ok) {
    try {
      await store.recordReconciliation({ refundId: request.refundId, reason: validated.reason, candidateRefundIds: [] });
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'RECONCILIATION_WRITE_FAILED');
    }
    return await markUnknown(store, request.refundId, leaseToken, validated.reason);
  }
  if (validated.value.id !== request.knownProviderRefundId) {
    try {
      await store.recordReconciliation({ refundId: request.refundId, reason: 'PROVIDER_REFUND_ID_CONFLICT', candidateRefundIds: [validated.value.id] });
    } catch {
      return await markUnknown(store, request.refundId, leaseToken, 'RECONCILIATION_WRITE_FAILED');
    }
    return await markUnknown(store, request.refundId, leaseToken, 'PROVIDER_REFUND_ID_CONFLICT');
  }
  return await writeResult(store, request, leaseToken, validated.value);
}

async function writeResult(
  store: RefundDispatchStore,
  request: RefundRequestSnapshot,
  leaseToken: string,
  value: { id: string; payment_id: string; amount: number; currency: string; status: string; receipt: string | null },
): Promise<DispatchOutcome> {
  try {
    await store.recordValidatedResult({
      refundId: request.refundId,
      leaseToken,
      providerRefundId: value.id,
      providerStatus: value.status as 'pending' | 'processed' | 'failed',
      paymentId: value.payment_id,
      amountPaise: value.amount,
      currency: value.currency,
      receipt: value.receipt,
    });
  } catch {
    return await markUnknown(store, request.refundId, leaseToken, 'DATABASE_RESULT_WRITE_FAILED');
  }
  return { state: 'submitted', providerStatus: value.status as 'pending' | 'processed' | 'failed' };
}

async function markUnknown(
  store: RefundDispatchStore,
  refundId: string,
  leaseToken: string,
  reason: string,
): Promise<DispatchOutcome> {
  try {
    await store.markUnknown({ refundId, leaseToken, reason });
    return { state: 'unknown', reason };
  } catch {
    // The lease expiry is the final recovery mechanism when even the state
    // write cannot be persisted.
    return { state: 'result_write_failed', reason };
  }
}
