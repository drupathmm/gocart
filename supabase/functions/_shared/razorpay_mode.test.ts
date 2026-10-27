import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { isRazorpayTestKeyId } from './razorpay_mode.ts';

test('Razorpay order creation accepts only test key identifiers', () => {
  assert.equal(isRazorpayTestKeyId('rzp_test_public123'), true);
  assert.equal(isRazorpayTestKeyId('rzp_live_public123'), false);
  assert.equal(isRazorpayTestKeyId('rzp_test_'), false);
  assert.equal(isRazorpayTestKeyId('rzp_test_public123\n'), false);
});
