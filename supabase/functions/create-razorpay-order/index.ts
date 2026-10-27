import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { corsHeaders, errorResponse, jsonResponse } from '../_shared/cors.ts';
import { isRazorpayTestKeyId } from '../_shared/razorpay_mode.ts';
import { dispatchAfterClaim } from '../_shared/razorpay_order_dispatch.ts';

type ProviderOrder = {
  id?: unknown;
  receipt?: unknown;
  amount?: unknown;
  currency?: unknown;
};

function isExpectedProviderOrder(
  order: ProviderOrder,
  receipt: string,
  amountPaise: number,
): order is ProviderOrder & { id: string } {
  return typeof order.id === 'string' && order.id.length > 0
    && order.receipt === receipt
    && order.amount === amountPaise
    && order.currency === 'INR';
}

function paymentPayload(
  orderId: string,
  providerOrderId: string,
  keyId: string,
  amountPaise: number,
) {
  return {
    order_id: orderId,
    razorpay_order_id: providerOrderId,
    razorpay_key_id: keyId,
    amount: amountPaise,
    currency: 'INR',
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Use POST.');

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return errorResponse(401, 'NOT_AUTHENTICATED', 'Missing Authorization header.');

  let body: Record<string, unknown>;
  try {
    body = (await req.json()) as Record<string, unknown>;
  } catch {
    return errorResponse(400, 'INVALID_BODY', 'Request body must be JSON.');
  }
  const orderId = typeof body.order_id === 'string' ? body.order_id.trim() : '';
  if (!orderId) return errorResponse(400, 'INVALID_BODY', 'order_id is required.');
  const idempotencyKey = req.headers.get('Idempotency-Key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return errorResponse(400, 'INVALID_IDEMPOTENCY_KEY', 'Idempotency-Key must be between 8 and 128 characters.');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const keyId = Deno.env.get('RAZORPAY_KEY_ID') ?? '';
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET') ?? '';
  if (!supabaseUrl || !anonKey || !serviceKey || !keyId || !keySecret) {
    return errorResponse(500, 'PAYMENT_NOT_CONFIGURED', 'Payment creation is not configured.');
  }
  // This project is not approved for live payments. Refuse to create even a
  // provider order unless the server is configured with a Razorpay test key.
  if (!isRazorpayTestKeyId(keyId)) {
    return errorResponse(503, 'TEST_MODE_ONLY', 'Only Razorpay test mode is enabled.');
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) return errorResponse(401, 'NOT_AUTHENTICATED', 'Invalid session.');

  const admin = createClient(supabaseUrl, serviceKey);
  const { data: claimRows, error: claimError } = await admin.rpc('claim_razorpay_order_with_key_recoverable', {
    p_order_id: orderId,
    p_buyer_id: user.id,
    p_idempotency_key: idempotencyKey,
  });
  if (claimError || !Array.isArray(claimRows) || claimRows.length !== 1) {
    const message = claimError?.message ?? '';
    const code = message.includes('ORDER_NOT_FOUND') ? 'ORDER_NOT_FOUND'
      : message.includes('ORDER_NOT_PAYABLE') ? 'ORDER_NOT_PAYABLE'
      : message.includes('IDEMPOTENCY_CONFLICT') ? 'IDEMPOTENCY_CONFLICT'
      : message.includes('PAYMENT_ORDER_IN_PROGRESS') ? 'PAYMENT_ORDER_IN_PROGRESS'
      : 'PAYMENT_ORDER_CLAIM_FAILED';
    return errorResponse(code === 'ORDER_NOT_FOUND' ? 404 : 409, code, code);
  }

  const claim = claimRows[0] as {
    claim_state: string;
    claim_token: string | null;
    provider_order_id: string | null;
    amount_paise: number | string;
    currency: string;
    response_payload: unknown;
  };
  if (claim.claim_state === 'cached') {
    if (isRecord(claim.response_payload)) return jsonResponse(claim.response_payload);
    return errorResponse(409, 'INVALID_CACHED_PAYMENT_RESPONSE', 'The saved payment response is invalid.');
  }
  const amountPaise = Number(claim.amount_paise);
  if (!Number.isSafeInteger(amountPaise) || amountPaise <= 0 || claim.currency !== 'INR') {
    return errorResponse(409, 'INVALID_EXPECTED_AMOUNT', 'The saved order amount is invalid.');
  }

  if (claim.claim_state === 'created' && claim.provider_order_id) {
    const { data: responsePayload, error } = await admin.rpc('cache_razorpay_order_response', {
      p_order_id: orderId,
      p_idempotency_key: idempotencyKey,
      p_response_payload: paymentPayload(orderId, claim.provider_order_id, keyId, amountPaise),
    });
    if (error || !isRecord(responsePayload)) {
      return errorResponse(409, 'PAYMENT_ORDER_SAVE_FAILED', 'Provider order needs reconciliation.');
    }
    return jsonResponse(responsePayload);
  }
  if (claim.claim_state === 'in_progress') {
    return errorResponse(409, 'PAYMENT_ORDER_IN_PROGRESS', 'Payment order creation is already in progress. Retry with the same key.');
  }
  if (!claim.claim_token) {
    return errorResponse(409, 'PAYMENT_ORDER_RECOVERY_REQUIRED', 'Payment order requires reconciliation.');
  }

  const completeProviderOrder = async (providerOrder: ProviderOrder) => {
    if (!isExpectedProviderOrder(providerOrder, orderId, amountPaise)) {
      return errorResponse(409, 'PROVIDER_ORDER_MISMATCH', 'Provider order does not match the saved GoCart order.');
    }
    const { data: responsePayload, error } = await admin.rpc('complete_razorpay_order_cached', {
      p_order_id: orderId,
      p_claim_token: claim.claim_token,
      p_provider_order_id: providerOrder.id,
      p_idempotency_key: idempotencyKey,
      p_response_payload: paymentPayload(orderId, providerOrder.id, keyId, amountPaise),
    });
    if (error || !isRecord(responsePayload)) {
      return errorResponse(409, 'PAYMENT_ORDER_SAVE_FAILED', 'Provider order needs reconciliation.');
    }
    return jsonResponse(responsePayload);
  };

  // A prior call may have reached Razorpay but died before saving its response.
  // Razorpay supports filtering order listings by receipt; reconcile that
  // deterministic receipt before ever issuing another create request.
  if (claim.claim_state === 'reconcile') {
    try {
      const recoveryResponse = await fetch(
        `https://api.razorpay.com/v1/orders?receipt=${encodeURIComponent(orderId)}&count=100`,
        {
          headers: {
            Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
            Accept: 'application/json',
          },
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!recoveryResponse.ok) {
        return errorResponse(502, 'PROVIDER_RECONCILIATION_UNAVAILABLE', 'Could not reconcile the payment order.');
      }
      const listing = await recoveryResponse.json() as { items?: ProviderOrder[] };
      const matches = (listing.items ?? []).filter((item) => item.receipt === orderId);
      if (matches.length === 1) return await completeProviderOrder(matches[0]);
      if (matches.length > 1) {
        return errorResponse(409, 'DUPLICATE_PROVIDER_ORDERS', 'Multiple provider orders require manual reconciliation.');
      }
    } catch {
      return errorResponse(502, 'PROVIDER_RECONCILIATION_UNAVAILABLE', 'Could not reconcile the payment order.');
    }
    const { error } = await admin.rpc('mark_razorpay_order_recovery', {
      p_order_id: orderId,
      p_claim_token: claim.claim_token,
    });
    if (error) return errorResponse(409, 'PAYMENT_ORDER_RECOVERY_REQUIRED', 'Payment order requires reconciliation.');
    return errorResponse(409, 'PAYMENT_ORDER_RECOVERY_REQUIRED', 'No provider order was found; automatic recreation is blocked.');
  }

  if (claim.claim_state !== 'claimed') {
    return errorResponse(409, 'PAYMENT_ORDER_RECOVERY_REQUIRED', 'Payment order requires reconciliation.');
  }

  try {
    const dispatch = await dispatchAfterClaim(
      async () => admin.rpc('mark_razorpay_order_dispatch_started', {
        p_order_id: orderId,
        p_claim_token: claim.claim_token!,
      }),
      () => fetch('https://api.razorpay.com/v1/orders', {
        method: 'POST',
        headers: {
          Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({
          amount: amountPaise,
          currency: 'INR',
          receipt: orderId,
          notes: { gocart_order_id: orderId },
        }),
        signal: AbortSignal.timeout(10000),
      }),
    );
    if (dispatch.state === 'not_marked') {
      return errorResponse(409, 'PAYMENT_ORDER_CLAIM_CONFLICT', 'Payment order claim expired. Retry with the same key.');
    }
    const response = dispatch.response;
    if (!response.ok) {
      await admin.rpc('mark_razorpay_order_recovery', {
        p_order_id: orderId,
        p_claim_token: claim.claim_token,
      });
      return errorResponse(502, 'RAZORPAY_ERROR', 'Provider order outcome requires reconciliation.');
    }
    const providerOrder = await response.json() as ProviderOrder;
    return await completeProviderOrder(providerOrder);
  } catch {
    await admin.rpc('mark_razorpay_order_recovery', {
      p_order_id: orderId,
      p_claim_token: claim.claim_token,
    });
    return errorResponse(502, 'RAZORPAY_ERROR', 'Provider order outcome requires reconciliation.');
  }
});
