import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  validateCapturedPayment,
  verifyCheckoutSignature,
  type RazorpayPayment,
} from './razorpay_payment_validation.ts';

const expected = {
  paymentId: 'pay_test_123',
  orderId: 'order_test_123',
  amountPaise: 12345,
  currency: 'INR',
};

const capturedPayment: RazorpayPayment = {
  id: expected.paymentId,
  order_id: expected.orderId,
  amount: expected.amountPaise,
  currency: expected.currency,
  status: 'captured',
  captured: true,
};

test('accepts only the expected captured payment', () => {
  assert.equal(validateCapturedPayment(capturedPayment, expected), null);
});

test('rejects a payment attached to a different provider order', () => {
  assert.equal(
    validateCapturedPayment({ ...capturedPayment, order_id: 'order_other' }, expected),
    'PROVIDER_ORDER_MISMATCH',
  );
});

test('rejects amount and currency mismatches', () => {
  assert.equal(
    validateCapturedPayment({ ...capturedPayment, amount: expected.amountPaise - 1 }, expected),
    'PAYMENT_AMOUNT_MISMATCH',
  );
  assert.equal(
    validateCapturedPayment({ ...capturedPayment, currency: 'USD' }, expected),
    'PAYMENT_CURRENCY_MISMATCH',
  );
});

test('rejects authorized-only and failed payments', () => {
  assert.equal(
    validateCapturedPayment({ ...capturedPayment, status: 'authorized', captured: false }, expected),
    'PAYMENT_NOT_CAPTURED',
  );
  assert.equal(
    validateCapturedPayment({ ...capturedPayment, status: 'failed', captured: false }, expected),
    'PAYMENT_NOT_CAPTURED',
  );
});

test('validates the checkout HMAC and rejects altered fields', async () => {
  const secret = 'local-test-secret-only';
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const digest = await crypto.subtle.sign(
    'HMAC', key, new TextEncoder().encode(`${expected.orderId}|${expected.paymentId}`),
  );
  const signature = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0')).join('');

  assert.equal(await verifyCheckoutSignature(secret, expected.orderId, expected.paymentId, signature), true);
  assert.equal(await verifyCheckoutSignature(secret, 'order_other', expected.paymentId, signature), false);
  assert.equal(await verifyCheckoutSignature(secret, expected.orderId, expected.paymentId, 'not-hex'), false);
});
