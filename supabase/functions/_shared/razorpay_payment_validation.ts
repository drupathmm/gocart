export type RazorpayPayment = {
  id?: unknown;
  order_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  status?: unknown;
  captured?: unknown;
};

export type ExpectedRazorpayPayment = {
  paymentId: string;
  orderId: string;
  amountPaise: number;
  currency: string;
};

export type PaymentValidationCode =
  | 'PROVIDER_PAYMENT_MISMATCH'
  | 'PROVIDER_ORDER_MISMATCH'
  | 'PAYMENT_NOT_CAPTURED'
  | 'PAYMENT_AMOUNT_MISMATCH'
  | 'PAYMENT_CURRENCY_MISMATCH';

export async function verifyCheckoutSignature(
  secret: string,
  orderId: string,
  paymentId: string,
  suppliedSignature: string,
): Promise<boolean> {
  if (!/^[a-f0-9]{64}$/i.test(suppliedSignature)) return false;
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const digest = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`${orderId}|${paymentId}`),
  );
  const expected = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
  let mismatch = expected.length ^ suppliedSignature.length;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ (suppliedSignature.toLowerCase().charCodeAt(i) || 0);
  }
  return mismatch === 0;
}

export function validateCapturedPayment(
  payment: RazorpayPayment,
  expected: ExpectedRazorpayPayment,
): PaymentValidationCode | null {
  if (payment.id !== expected.paymentId) return 'PROVIDER_PAYMENT_MISMATCH';
  if (payment.order_id !== expected.orderId) return 'PROVIDER_ORDER_MISMATCH';
  if (payment.status !== 'captured' || payment.captured !== true) {
    return 'PAYMENT_NOT_CAPTURED';
  }
  if (payment.amount !== expected.amountPaise) return 'PAYMENT_AMOUNT_MISMATCH';
  if (payment.currency !== expected.currency) return 'PAYMENT_CURRENCY_MISMATCH';
  return null;
}
