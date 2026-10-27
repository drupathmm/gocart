import { type ExpectedRazorpayPayment, type RazorpayPayment } from './razorpay_payment_validation.ts';

export type ProviderPayment = RazorpayPayment & {
  entity?: unknown;
  refund_status?: unknown;
  amount_refunded?: unknown;
  amount_captured?: unknown;
};

export type PaymentCollection = { entity?: unknown; count?: unknown; items?: unknown };
export type ProviderOrder = {
  id?: unknown; receipt?: unknown; amount?: unknown; currency?: unknown; attempts?: unknown;
};
export type RefundAssessment = { present: boolean; malformed: boolean };
export type PaymentCollectionAssessment = {
  malformedPayment: boolean;
  malformedRefund: boolean;
  refundEvidence: boolean;
  unresolvedSibling: boolean;
  capturedPayments: ProviderPayment[];
};

export function assessRefundEvidence(payment: ProviderPayment): RefundAssessment {
  const hasStatus = Object.prototype.hasOwnProperty.call(payment, 'refund_status');
  const hasAmount = Object.prototype.hasOwnProperty.call(payment, 'amount_refunded');
  const status = payment.refund_status;
  const amount = payment.amount;
  const refunded = payment.amount_refunded;
  const total = typeof amount === 'number' && Number.isSafeInteger(amount) && amount >= 0 ? amount : null;
  const validRefund = typeof refunded === 'number' && Number.isSafeInteger(refunded)
    && refunded >= 0 && total !== null && refunded <= total;
  let malformed = (hasStatus && status !== null && status !== 'partial' && status !== 'full')
    || (hasAmount && !validRefund);
  if (validRefund && total !== null) {
    if ((!hasStatus || status === null) && refunded > 0) malformed = true;
    if (status === 'partial' && (refunded <= 0 || refunded >= total)) malformed = true;
    if (status === 'full' && refunded !== total) malformed = true;
  }
  if (payment.status === 'refunded') {
    if (hasStatus && status !== 'full') malformed = true;
    if (hasAmount && (!validRefund || refunded !== total)) malformed = true;
  }
  if ((payment.status === 'created' || payment.status === 'authorized' || payment.status === 'failed')
      && ((hasStatus && status !== null) || (validRefund && refunded > 0))) malformed = true;
  return {
    present: payment.status === 'refunded' || status === 'partial' || status === 'full'
      || (validRefund && refunded > 0),
    malformed,
  };
}

function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function paymentCollectionCompletenessCode(
  collection: PaymentCollection,
  providerAttemptCount: unknown,
): string | null {
  if (collection.entity !== 'collection' || !Number.isSafeInteger(collection.count)
      || (collection.count as number) < 0 || !Array.isArray(collection.items)
      || !Number.isSafeInteger(providerAttemptCount) || (providerAttemptCount as number) < 0
      || collection.items.length !== collection.count
      || collection.count !== providerAttemptCount) {
    return 'PROVIDER_PAYMENT_LIST_INCOMPLETE';
  }
  return null;
}

export function assessPaymentCollectionItems(
  collection: PaymentCollection,
  expected: { orderId: string; amountPaise: number; currency: string },
): PaymentCollectionAssessment {
  const result: PaymentCollectionAssessment = {
    malformedPayment: false, malformedRefund: false, refundEvidence: false,
    unresolvedSibling: false, capturedPayments: [],
  };
  if (!Array.isArray(collection.items)) {
    result.malformedPayment = true;
    return result;
  }
  const paymentIds = new Set<string>();
  for (const raw of collection.items) {
    if (!object(raw)) { result.malformedPayment = true; continue; }
    const payment = raw as ProviderPayment;
    if (typeof payment.id === 'string' && paymentIds.has(payment.id)) result.malformedPayment = true;
    if (typeof payment.id === 'string') paymentIds.add(payment.id);
    const refund = assessRefundEvidence(payment);
    result.refundEvidence ||= refund.present;
    result.malformedRefund ||= refund.malformed;
    if (payment.entity !== 'payment' || typeof payment.id !== 'string' || payment.id.length === 0
        || payment.order_id !== expected.orderId || payment.amount !== expected.amountPaise
        || payment.currency !== expected.currency
        || !['created', 'authorized', 'captured', 'refunded', 'failed'].includes(String(payment.status))
        || typeof payment.captured !== 'boolean') {
      result.malformedPayment = true;
      continue;
    }
    if (payment.status === 'created' || payment.status === 'authorized' || payment.status === 'failed') {
      result.unresolvedSibling = true;
    }
    const isCapturedState = payment.status === 'captured' || payment.status === 'refunded';
    if (isCapturedState !== (payment.captured === true)) result.malformedPayment = true;
    if (payment.amount_captured !== undefined && payment.amount_captured !== null
        && (typeof payment.amount_captured !== 'number'
          || !Number.isSafeInteger(payment.amount_captured)
          || payment.amount_captured < 0 || payment.amount_captured > expected.amountPaise
          || (isCapturedState && payment.amount_captured !== expected.amountPaise)
          || (!isCapturedState && payment.amount_captured > 0))) {
      result.malformedPayment = true;
    }
    if (payment.status === 'captured' && payment.captured === true) result.capturedPayments.push(payment);
  }
  return result;
}

/**
 * A provider collection is the only trusted source for sibling attempts.  A
 * malformed or partial collection is deliberately a review result, never a
 * reason to accept a capture based on one payment detail response.
 */
export function capturedPaymentCollectionReviewCode(
  collection: PaymentCollection,
  expected: ExpectedRazorpayPayment & { receipt: string },
  providerOrder: ProviderOrder,
): string | null {
  if (providerOrder.id !== expected.orderId || providerOrder.receipt !== expected.receipt
      || providerOrder.amount !== expected.amountPaise || providerOrder.currency !== expected.currency
      || !Number.isSafeInteger(providerOrder.attempts) || (providerOrder.attempts as number) < 0) {
    return 'PROVIDER_ORDER_MISMATCH';
  }
  if (paymentCollectionCompletenessCode(collection, providerOrder.attempts)) {
    return 'PROVIDER_PAYMENT_LIST_INCOMPLETE';
  }
  const assessment = assessPaymentCollectionItems(collection, expected);
  if (assessment.malformedRefund) return 'PROVIDER_REFUND_DATA_INVALID';
  if (assessment.refundEvidence) return 'PROVIDER_REFUND_STATE_UNSUPPORTED';
  if (assessment.malformedPayment) return 'PROVIDER_PAYMENT_MISMATCH';
  if (assessment.capturedPayments.length !== 1) return assessment.capturedPayments.length > 1
    ? 'MULTIPLE_CAPTURED_PAYMENTS' : 'PROVIDER_PAYMENT_MISMATCH';
  if (assessment.capturedPayments[0].id !== expected.paymentId) return 'PROVIDER_PAYMENT_MISMATCH';
  return assessment.unresolvedSibling ? 'UNRESOLVED_SIBLING_PAYMENT' : null;
}
