import type {
  PaymentCollection,
  ProviderOrder,
  ProviderPayment,
} from './razorpay_reconciliation_handler.ts';

export type RazorpayReadFetcher = (
  input: string | URL,
  init?: RequestInit,
) => Promise<Response>;

async function getProviderJson(
  path: string,
  keyId: string,
  keySecret: string,
  fetcher: RazorpayReadFetcher,
): Promise<Record<string, unknown>> {
  const response = await fetcher(`https://api.razorpay.com/v1/${path}`, {
    method: 'GET',
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      Accept: 'application/json',
    },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error('PROVIDER_LOOKUP_FAILED');
  if (Number(response.headers.get('content-length') ?? '0') > 1_000_000) {
    await response.body?.cancel();
    throw new Error('PROVIDER_RESPONSE_TOO_LARGE');
  }
  if (!response.body) throw new Error('INVALID_PROVIDER_RESPONSE');

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > 1_000_000) {
      await reader.cancel();
      throw new Error('PROVIDER_RESPONSE_TOO_LARGE');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error('INVALID_PROVIDER_RESPONSE');
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('INVALID_PROVIDER_RESPONSE');
  }
  return value as Record<string, unknown>;
}

export function createRazorpayReconciliationReader(
  keyId: string,
  keySecret: string,
  fetcher: RazorpayReadFetcher = fetch,
): {
  fetchProviderOrder: (providerOrderId: string) => Promise<ProviderOrder>;
  fetchProviderOrderPayments: (providerOrderId: string) => Promise<PaymentCollection>;
  fetchProviderPayment: (paymentId: string) => Promise<ProviderPayment>;
} {
  return {
    fetchProviderOrder: async (providerOrderId) => await getProviderJson(
      `orders/${encodeURIComponent(providerOrderId)}`, keyId, keySecret, fetcher,
    ) as ProviderOrder,
    fetchProviderOrderPayments: async (providerOrderId) => await getProviderJson(
      `orders/${encodeURIComponent(providerOrderId)}/payments`, keyId, keySecret, fetcher,
    ) as PaymentCollection,
    fetchProviderPayment: async (paymentId) => await getProviderJson(
      `payments/${encodeURIComponent(paymentId)}`, keyId, keySecret, fetcher,
    ) as ProviderPayment,
  };
}
