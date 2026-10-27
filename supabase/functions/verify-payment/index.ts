import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { isRazorpayTestKeyId } from '../_shared/razorpay_mode.ts';
import { handleVerifyPayment } from '../_shared/verify_payment_handler.ts';

Deno.serve((req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const keyId = Deno.env.get('RAZORPAY_KEY_ID') ?? '';
  const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET') ?? '';
  const configured = Boolean(
    supabaseUrl && anonKey && serviceKey && keySecret && isRazorpayTestKeyId(keyId),
  );
  let admin: ReturnType<typeof createClient> | null = null;
  const getAdmin = () => admin ??= createClient(supabaseUrl, serviceKey);

  return handleVerifyPayment(req, {
    configured,
    keySecret,
    authenticate: async (authorization) => {
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authorization } },
      });
      const { data: { user }, error } = await userClient.auth.getUser();
      if (error || !user) return null;
      return { id: user.id };
    },
    loadOrder: async (orderId) => {
      const { data, error } = await getAdmin()
        .from('orders')
        .select('id, user_id, status, payment_status, razorpay_order_id')
        .eq('id', orderId)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    loadAttempt: async (orderId) => {
      const { data, error } = await getAdmin()
        .from('razorpay_payment_attempts')
        .select('provider_order_id, expected_amount_paise, currency, state, provider_payment_id')
        .eq('order_id', orderId)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    fetchProviderPayment: async (paymentId) => {
      const response = await fetch(
        `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
        {
          headers: {
            Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
            Accept: 'application/json',
          },
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!response.ok) throw new Error('Provider verification unavailable.');
      return await response.json();
    },
    fetchProviderOrder: async (providerOrderId) => {
      const response = await fetch(`https://api.razorpay.com/v1/orders/${encodeURIComponent(providerOrderId)}`, {
        headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('Provider order lookup unavailable.');
      return await response.json();
    },
    fetchProviderOrderPayments: async (providerOrderId) => {
      const response = await fetch(`https://api.razorpay.com/v1/orders/${encodeURIComponent(providerOrderId)}/payments`, {
        headers: { Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`, Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('Provider payment list unavailable.');
      return await response.json();
    },
    recordVerifiedPayment: async (input) => {
      const { data, error } = await getAdmin().rpc('record_verified_razorpay_payment', {
        p_order_id: input.orderId,
        p_buyer_id: input.buyerId,
        p_provider_order_id: input.providerOrderId,
        p_provider_payment_id: input.providerPaymentId,
        p_amount_paise: input.amountPaise,
        p_currency: input.currency,
      });
      return error ? { error: error.message } : { result: data };
    },
    recordPaymentReview: async (input) => {
      const { data, error } = await getAdmin().rpc('record_razorpay_payment_review', {
        p_order_id: input.orderId, p_buyer_id: input.buyerId, p_provider_order_id: input.providerOrderId,
        p_provider_payment_id: input.providerPaymentId, p_amount_paise: input.amountPaise,
        p_currency: input.currency, p_reason: input.reason,
        p_review_outcome: input.reviewOutcome,
      });
      return error ? { error: error.message } : { result: data };
    },
    claimVerification: async (input) => {
      const { data, error } = await getAdmin().rpc('claim_payment_verification', {
        p_user_id: input.userId,
        p_order_id: input.orderId,
        p_idempotency_key: input.idempotencyKey,
      });
      if (error) return { error: error.message };
      if (!Array.isArray(data) || data.length !== 1) {
        return { error: 'PAYMENT_VERIFICATION_CLAIM_FAILED' };
      }
      const claim = data[0] as {
        claim_state: string;
        claim_token: string | null;
        response_payload: unknown;
      };
      return {
        claimState: claim.claim_state,
        claimToken: claim.claim_token,
        responsePayload: claim.response_payload,
      };
    },
    cacheVerificationResponse: async (input) => {
      const { data, error } = await getAdmin().rpc('cache_payment_verification_response', {
        p_user_id: input.userId,
        p_order_id: input.orderId,
        p_idempotency_key: input.idempotencyKey,
        p_claim_token: input.claimToken,
        p_response_payload: input.responsePayload,
      });
      return error ? { error: error.message } : { responsePayload: data };
    },
    releaseVerificationClaim: async (input) => {
      await getAdmin().rpc('release_payment_verification_claim', {
        p_idempotency_key: input.idempotencyKey,
        p_claim_token: input.claimToken,
      });
    },
    loadFinalOrder: async (orderId) => {
      const { data, error } = await getAdmin()
        .from('orders')
        .select('status, payment_status')
        .eq('id', orderId)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });
});
