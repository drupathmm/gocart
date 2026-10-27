import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { corsHeaders, errorResponse, jsonResponse } from '../_shared/cors.ts';
import { mapPlaceOrderError } from '../_shared/checkout_error_mapping.ts';

type CheckoutBody = {
  offer_code?: unknown;
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return errorResponse(405, 'METHOD_NOT_ALLOWED', 'Use POST.');
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(401, 'NOT_AUTHENTICATED', 'Missing Authorization header.');
  }

  let body: CheckoutBody;
  try {
    body = (await req.json()) as CheckoutBody;
  } catch {
    return errorResponse(400, 'INVALID_BODY', 'Request body must be JSON.');
  }

  const idempotencyKey = req.headers.get('Idempotency-Key')?.trim() ?? '';
  if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 128) {
    return errorResponse(
      400,
      'INVALID_IDEMPOTENCY_KEY',
      'Idempotency-Key must be between 8 and 128 characters.',
    );
  }

  let offerCode: string | null = null;
  if (body.offer_code != null && body.offer_code !== '') {
    if (typeof body.offer_code !== 'string') {
      return errorResponse(400, 'INVALID_BODY', 'offer_code must be a string.');
    }
    offerCode = body.offer_code.trim();
    if (offerCode.length > 64) {
      return errorResponse(400, 'INVALID_BODY', 'offer_code is too long.');
    }
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('checkout configuration missing required Supabase settings');
    return errorResponse(503, 'CHECKOUT_UNAVAILABLE', 'Checkout is temporarily unavailable.');
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();
  if (userError || !user) {
    return errorResponse(401, 'NOT_AUTHENTICATED', 'Invalid session.');
  }

  const { data: responsePayload, error: rpcError } = await supabase.rpc(
    'checkout_place_order_cached',
    {
      p_offer_code: offerCode,
      p_idempotency_key: idempotencyKey,
    },
  );

  if (rpcError) {
    console.error('checkout RPC failed', {
      code: rpcError.code ?? 'UNKNOWN',
      message: (rpcError.message ?? 'unknown').slice(0, 240),
    });
    const mapped = mapPlaceOrderError(rpcError.message ?? '');
    return errorResponse(mapped.status, mapped.code, mapped.code);
  }

  if (!responsePayload || typeof responsePayload !== 'object' || Array.isArray(responsePayload)) {
    return errorResponse(500, 'CHECKOUT_FAILED', 'The saved checkout response is invalid.');
  }

  return jsonResponse(responsePayload);
});
