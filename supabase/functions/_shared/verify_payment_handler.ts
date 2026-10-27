import { corsHeaders, errorResponse, jsonResponse } from './cors.ts';
import {
  validateCapturedPayment,
  verifyCheckoutSignature,
  type RazorpayPayment,
} from './razorpay_payment_validation.ts';
import {
  capturedPaymentCollectionReviewCode,
  type PaymentCollection,
  type ProviderOrder,
} from './razorpay_payment_collection_validation.ts';

type OrderRecord = {
  id: string;
  user_id: string;
  status: string;
  payment_status: string;
  razorpay_order_id: string | null;
};

type AttemptRecord = {
  provider_order_id: string | null;
  expected_amount_paise: number | string;
  currency: string;
  state: string;
  provider_payment_id: string | null;
};

export type VerifyPaymentDependencies = {
  configured: boolean;
  keySecret: string;
  authenticate: (authorization: string) => Promise<{ id: string } | null>;
  loadOrder: (orderId: string) => Promise<OrderRecord | null>;
  loadAttempt: (orderId: string) => Promise<AttemptRecord | null>;
  fetchProviderPayment: (paymentId: string) => Promise<RazorpayPayment>;
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
    amountPaise: number; currency: string; reason: string; reviewOutcome: 'capture_confirmed';
  }) => Promise<{ result?: string; error?: string }>;
  claimVerification: (input: {
    userId: string;
    orderId: string;
    idempotencyKey: string;
  }) => Promise<{
    claimState?: string;
    claimToken?: string | null;
    responsePayload?: unknown;
    error?: string;
  }>;
  cacheVerificationResponse: (input: {
    userId: string;
    orderId: string;
    idempotencyKey: string;
    claimToken: string;
    responsePayload: Record<string, unknown>;
  }) => Promise<{ responsePayload?: unknown; error?: string }>;
  releaseVerificationClaim: (input: {
    idempotencyKey: string;
    claimToken: string;
  }) => Promise<void>;
  loadFinalOrder: (orderId: string) => Promise<{
    status: string;
    payment_status: string;
  } | null>;
};

export async function handleVerifyPayment(
  req: Request,
  dependencies: VerifyPaymentDependencies,
): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Use POST.');

  const authorization = req.headers.get('Authorization');
  if (!authorization) return errorResponse(401, 'NOT_AUTHENTICATED', 'Missing Authorization header.');

  let body: Record<string, unknown>;
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return errorResponse(400, 'INVALID_BODY', 'Request body must be JSON.');
  }

  const orderId = typeof body.order_id === 'string' ? body.order_id.trim() : '';
  const providerOrderId = typeof body.razorpay_order_id === 'string'
    ? body.razorpay_order_id.trim()
    : '';
  const paymentId = typeof body.razorpay_payment_id === 'string'
    ? body.razorpay_payment_id.trim()
    : '';
  const signature = typeof body.razorpay_signature === 'string'
    ? body.razorpay_signature.trim()
    : '';
  if (!orderId || !providerOrderId || !paymentId || !signature) {
    return errorResponse(400, 'INVALID_BODY', 'Order, payment, and signature fields are required.');
  }
  const idempotencyKey = req.headers.get('Idempotency-Key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return errorResponse(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be between 8 and 128 characters.');
  }
  if (!dependencies.configured) {
    return errorResponse(500, 'PAYMENT_NOT_CONFIGURED', 'Payment verification is not configured.');
  }

  let user: { id: string } | null;
  try {
    user = await dependencies.authenticate(authorization);
  } catch {
    user = null;
  }
  if (!user) return errorResponse(401, 'NOT_AUTHENTICATED', 'Invalid session.');

  let order: OrderRecord | null;
  try {
    order = await dependencies.loadOrder(orderId);
  } catch {
    order = null;
  }
  if (!order) return errorResponse(404, 'ORDER_NOT_FOUND', 'Order not found.');
  if (order.user_id !== user.id) {
    return errorResponse(403, 'NOT_AUTHORIZED', 'This order does not belong to you.');
  }

  let attempt: AttemptRecord | null;
  try {
    attempt = await dependencies.loadAttempt(order.id);
  } catch {
    attempt = null;
  }
  if (!attempt) return errorResponse(409, 'PAYMENT_ATTEMPT_NOT_FOUND', 'No payment attempt exists for this order.');
  if (attempt.provider_order_id !== providerOrderId || order.razorpay_order_id !== providerOrderId) {
    return errorResponse(409, 'PROVIDER_ORDER_MISMATCH', 'Payment belongs to a different provider order.');
  }

  if (!await verifyCheckoutSignature(dependencies.keySecret, providerOrderId, paymentId, signature)) {
    return errorResponse(400, 'INVALID_SIGNATURE', 'Payment signature is invalid.');
  }

  let verificationClaim: Awaited<ReturnType<VerifyPaymentDependencies['claimVerification']>>;
  try {
    verificationClaim = await dependencies.claimVerification({
      userId: user.id,
      orderId: order.id,
      idempotencyKey,
    });
  } catch {
    verificationClaim = { error: 'PAYMENT_VERIFICATION_CLAIM_FAILED' };
  }
  if (verificationClaim.error) {
    const code = verificationClaim.error.includes('IDEMPOTENCY_CONFLICT')
      ? 'IDEMPOTENCY_CONFLICT'
      : 'PAYMENT_VERIFICATION_CLAIM_FAILED';
    return errorResponse(409, code, code);
  }
  if (verificationClaim.claimState === 'cached') {
    if (
      verificationClaim.responsePayload !== null
      && typeof verificationClaim.responsePayload === 'object'
      && !Array.isArray(verificationClaim.responsePayload)
    ) {
      return jsonResponse(verificationClaim.responsePayload);
    }
    return errorResponse(409, 'INVALID_CACHED_PAYMENT_RESPONSE', 'The saved payment response is invalid.');
  }
  if (verificationClaim.claimState === 'in_progress') {
    return errorResponse(409, 'IDEMPOTENCY_IN_PROGRESS', 'Payment verification is already processing. Retry shortly.');
  }
  const claimToken = verificationClaim.claimToken;
  if (verificationClaim.claimState !== 'claimed' || !claimToken) {
    return errorResponse(409, 'PAYMENT_VERIFICATION_CLAIM_FAILED', 'Payment verification could not be claimed.');
  }
  const releaseClaim = async () => {
    try {
      await dependencies.releaseVerificationClaim({ idempotencyKey, claimToken });
    } catch {
      // The short database lease also recovers claims if this request disappears.
    }
  };

  let providerPayment: RazorpayPayment;
  try {
    providerPayment = await dependencies.fetchProviderPayment(paymentId);
  } catch {
    await releaseClaim();
    return errorResponse(502, 'PROVIDER_VERIFICATION_UNAVAILABLE', 'Could not verify payment with Razorpay.');
  }

  const amountPaise = Number(attempt.expected_amount_paise);
  const validationError = validateCapturedPayment(providerPayment, {
    paymentId,
    orderId: providerOrderId,
    amountPaise,
    currency: attempt.currency,
  });
  if (validationError) {
    await releaseClaim();
    return errorResponse(409, validationError, validationError);
  }

  if (attempt.state === 'captured_review' && attempt.provider_payment_id === paymentId) {
    const payload = {
      order_id: order.id,
      status: order.status,
      payment_status: order.payment_status,
      verification_result: 'review_required',
    };
    let cachedReview: Awaited<ReturnType<VerifyPaymentDependencies['cacheVerificationResponse']>>;
    try {
      cachedReview = await dependencies.cacheVerificationResponse({
        userId: user.id,
        orderId: order.id,
        idempotencyKey,
        claimToken,
        responsePayload: payload,
      });
    } catch {
      cachedReview = { error: 'PAYMENT_RESPONSE_SAVE_FAILED' };
    }
    if (cachedReview.error || cachedReview.responsePayload === null
        || typeof cachedReview.responsePayload !== 'object'
        || Array.isArray(cachedReview.responsePayload)) {
      await releaseClaim();
      return errorResponse(409, 'PAYMENT_RESPONSE_SAVE_FAILED', 'Payment was verified but its response could not be saved.');
    }
    return jsonResponse(cachedReview.responsePayload);
  }

  let reviewCode: string | null = null;
  try {
    const [providerOrder, collection] = await Promise.all([
      dependencies.fetchProviderOrder(providerOrderId),
      dependencies.fetchProviderOrderPayments(providerOrderId),
    ]);
    reviewCode = capturedPaymentCollectionReviewCode(collection,
      { paymentId, orderId: providerOrderId, amountPaise, currency: attempt.currency, receipt: order.id },
      providerOrder);
  } catch {
    reviewCode = 'PROVIDER_PAYMENT_LIST_UNAVAILABLE';
  }
  if (reviewCode) {
    let reviewed: { result?: string; error?: string };
    try {
      reviewed = await dependencies.recordPaymentReview({
        orderId: order.id, buyerId: user.id, providerOrderId, providerPaymentId: paymentId,
        amountPaise: providerPayment.amount as number, currency: providerPayment.currency as string,
        reason: reviewCode, reviewOutcome: 'capture_confirmed',
      });
    } catch { reviewed = { error: 'PAYMENT_REVIEW_UPDATE_FAILED' }; }
    if (reviewed.error) {
      await releaseClaim();
      return errorResponse(503, 'PAYMENT_REVIEW_UPDATE_FAILED', 'Payment requires durable review.');
    }
    let finalOrder: { status: string; payment_status: string } | null;
    try { finalOrder = await dependencies.loadFinalOrder(order.id); } catch { finalOrder = null; }
    if (!finalOrder) { await releaseClaim(); return errorResponse(500, 'PAYMENT_STATE_UNAVAILABLE', 'Payment review state could not be loaded.'); }
    const payload = { order_id: order.id, status: finalOrder.status, payment_status: finalOrder.payment_status,
      verification_result: 'review_required' };
    const cached = await dependencies.cacheVerificationResponse({ userId: user.id, orderId: order.id,
      idempotencyKey, claimToken, responsePayload: payload });
    if (cached.error || !cached.responsePayload || typeof cached.responsePayload !== 'object' || Array.isArray(cached.responsePayload)) {
      await releaseClaim(); return errorResponse(503, 'PAYMENT_RESPONSE_SAVE_FAILED', 'Payment review response could not be saved.');
    }
    return jsonResponse(cached.responsePayload);
  }

  let recorded: { result?: string; error?: string };
  try {
    recorded = await dependencies.recordVerifiedPayment({
      orderId: order.id,
      buyerId: user.id,
      providerOrderId,
      providerPaymentId: paymentId,
      amountPaise: providerPayment.amount as number,
      currency: providerPayment.currency as string,
    });
  } catch {
    recorded = { error: 'PAYMENT_UPDATE_FAILED' };
  }
  if (recorded.error) {
    await releaseClaim();
    const code = recorded.error.split(':').pop()?.trim() || 'PAYMENT_UPDATE_FAILED';
    return errorResponse(409, code, code);
  }

  let finalOrder: { status: string; payment_status: string } | null;
  try {
    finalOrder = await dependencies.loadFinalOrder(order.id);
  } catch {
    finalOrder = null;
  }
  if (!finalOrder) {
    await releaseClaim();
    return errorResponse(500, 'PAYMENT_STATE_UNAVAILABLE', 'Payment was checked but order state could not be loaded.');
  }

  const payload = {
    order_id: order.id,
    status: finalOrder.status,
    payment_status: finalOrder.payment_status,
    verification_result: recorded.result,
  };
  let cached: Awaited<ReturnType<VerifyPaymentDependencies['cacheVerificationResponse']>>;
  try {
    cached = await dependencies.cacheVerificationResponse({
      userId: user.id,
      orderId: order.id,
      idempotencyKey,
      claimToken,
      responsePayload: payload,
    });
  } catch {
    cached = { error: 'PAYMENT_RESPONSE_SAVE_FAILED' };
  }
  if (cached.error || cached.responsePayload === null
      || typeof cached.responsePayload !== 'object' || Array.isArray(cached.responsePayload)) {
    await releaseClaim();
    return errorResponse(409, 'PAYMENT_RESPONSE_SAVE_FAILED', 'Payment was verified but its response could not be saved.');
  }
  return jsonResponse(cached.responsePayload);
}
