import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { isRazorpayTestKeyId } from '../_shared/razorpay_mode.ts';
import { handleRazorpayWebhook } from '../_shared/razorpay_webhook_handler.ts';

Deno.serve((req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const webhookSecret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET') ?? '';
  const providerKeyId = Deno.env.get('RAZORPAY_KEY_ID') ?? '';
  const providerKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET') ?? '';
  const configured = Boolean(
    supabaseUrl && serviceKey && webhookSecret && providerKeySecret
      && isRazorpayTestKeyId(providerKeyId),
  );
  let admin: ReturnType<typeof createClient> | null = null;
  const getAdmin = () => admin ??= createClient(supabaseUrl, serviceKey);

  return handleRazorpayWebhook(req, {
    configured,
    webhookSecret,
    claimEvent: async (input) => {
      const { data, error } = await getAdmin().rpc('claim_razorpay_webhook_event', {
        p_event_id: input.eventId,
        p_event_type: input.eventType,
        p_provider_entity_id: input.providerEntityId,
      });
      if (error || !Array.isArray(data) || !data[0]) throw error ?? new Error('INVALID_EVENT_CLAIM');
      return data[0];
    },
    finishEvent: async (input) => {
      const { error } = await getAdmin().rpc('finish_razorpay_webhook_event', {
        p_event_id: input.eventId,
        p_lease_token: input.leaseToken,
        p_state: input.state,
        p_error_code: input.errorCode,
      });
      if (error) throw error;
    },
    loadAttemptByProviderOrder: async (providerOrderId) => {
      const { data, error } = await getAdmin()
        .from('razorpay_payment_attempts')
        .select('order_id, buyer_id, provider_order_id, expected_amount_paise, currency, state, provider_payment_id')
        .eq('provider_order_id', providerOrderId)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
    fetchProviderPayment: async (paymentId) => {
      const response = await fetch(
        `https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`,
        {
          headers: {
            Authorization: `Basic ${btoa(`${providerKeyId}:${providerKeySecret}`)}`,
            Accept: 'application/json',
          },
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!response.ok) throw new Error('PROVIDER_UNAVAILABLE');
      return await response.json();
    },
    fetchProviderOrder: async (providerOrderId) => {
      const response = await fetch(`https://api.razorpay.com/v1/orders/${encodeURIComponent(providerOrderId)}`, {
        headers: { Authorization: `Basic ${btoa(`${providerKeyId}:${providerKeySecret}`)}`, Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('PROVIDER_UNAVAILABLE');
      return await response.json();
    },
    fetchProviderOrderPayments: async (providerOrderId) => {
      const response = await fetch(`https://api.razorpay.com/v1/orders/${encodeURIComponent(providerOrderId)}/payments`, {
        headers: { Authorization: `Basic ${btoa(`${providerKeyId}:${providerKeySecret}`)}`, Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) throw new Error('PROVIDER_UNAVAILABLE');
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
    recordRefundWebhook: async (input) => {
      const { data, error } = await getAdmin().rpc('record_razorpay_refund_webhook', {
        p_event_id: input.eventId,
        p_event_type: input.eventType,
        p_provider_refund_id: input.providerRefundId,
        p_payment_id: input.paymentId,
        p_amount_paise: input.amountPaise,
        p_currency: input.currency,
        p_receipt: input.receipt,
        p_provider_status: input.providerStatus,
      });
      if (error) throw error;
      if (data !== 'recorded' && data !== 'reconciliation_required') {
        throw new Error('INVALID_REFUND_WEBHOOK_RESULT');
      }
      return data;
    },
  });
});
