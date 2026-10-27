import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { isRazorpayTestKeyId } from '../_shared/razorpay_mode.ts';
import {
  handleRazorpayReconciliation,
  type RazorpayReconciliationDependencies,
  type ReconciliationClaim,
} from '../_shared/razorpay_reconciliation_handler.ts';
import { createRazorpayReconciliationReader } from '../_shared/razorpay_reconciliation_provider.ts';

type RpcFinal = { response_payload?: unknown; http_status?: number };

function firstRow<T>(data: unknown): T | null {
  return Array.isArray(data) && data.length === 1 ? data[0] as T : null;
}

function finalResult(data: unknown, error: unknown): RpcFinal & { error?: string } {
  if (error) return { error: 'RPC_FAILED' };
  const result = data !== null && typeof data === 'object' && !Array.isArray(data)
    ? data as RpcFinal
    : null;
  if (!result || result.response_payload === null || result.response_payload === undefined) {
    return { error: 'INVALID_RPC_RESULT' };
  }
  return result;
}

Deno.serve((req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const razorpayKeyId = Deno.env.get('RAZORPAY_KEY_ID') ?? '';
  const razorpayKeySecret = Deno.env.get('RAZORPAY_KEY_SECRET') ?? '';
  const configured = Boolean(
    supabaseUrl && serviceRoleKey && razorpayKeySecret
      && isRazorpayTestKeyId(razorpayKeyId),
  );
  const providerReader = createRazorpayReconciliationReader(razorpayKeyId, razorpayKeySecret);

  let admin: ReturnType<typeof createClient> | null = null;
  const getAdmin = () => admin ??= createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const dependencies: RazorpayReconciliationDependencies = {
    configured,
    serviceRoleKey,
    claim: async (orderId, idempotencyKey) => {
      const { data, error } = await getAdmin().rpc('claim_razorpay_payment_reconciliation', {
        p_order_id: orderId,
        p_idempotency_key: idempotencyKey,
      });
      const claim = firstRow<ReconciliationClaim>(data);
      if (error) {
        const message = error !== null && typeof error === 'object'
          && 'message' in error && typeof error.message === 'string'
          ? error.message
          : '';
        return { error: message.includes('ORDER_NOT_FOUND') ? 'ORDER_NOT_FOUND' : 'CLAIM_UNAVAILABLE' };
      }
      if (!claim) return { error: 'INVALID_CLAIM_RESPONSE' };
      return { claim };
    },
    fetchProviderOrder: providerReader.fetchProviderOrder,
    fetchProviderOrderPayments: providerReader.fetchProviderOrderPayments,
    fetchProviderPayment: providerReader.fetchProviderPayment,
    finishDecision: async (input) => {
      const { data, error } = await getAdmin().rpc('finish_razorpay_payment_reconciliation', {
        p_run_id: input.runId,
        p_claim_token: input.claimToken,
        p_decision: input.decision,
        p_provider_order_status: input.providerOrderStatus,
        p_provider_attempt_count: input.providerAttemptCount,
        p_provider_payment_count: input.providerPaymentCount,
        p_evidence_sha256: input.evidenceSha256,
        p_evidence_summary: input.evidenceSummary,
        p_error_code: input.errorCode,
        p_response_http_status: input.httpStatus,
        p_response_payload: input.responsePayload,
      });
      return finalResult(data, error);
    },
    recordCapturedPayment: async (input) => {
      const { data, error } = await getAdmin().rpc('record_reconciled_razorpay_capture', {
        p_run_id: input.runId,
        p_claim_token: input.claimToken,
        p_provider_payment_id: input.providerPaymentId,
        p_amount_paise: input.amountPaise,
        p_currency: input.currency,
        p_provider_attempt_count: input.providerAttemptCount,
        p_provider_payment_count: input.providerPaymentCount,
        p_evidence_sha256: input.evidenceSha256,
        p_evidence_summary: input.evidenceSummary,
      });
      return finalResult(data, error);
    },
  };

  return handleRazorpayReconciliation(req, dependencies);
});
