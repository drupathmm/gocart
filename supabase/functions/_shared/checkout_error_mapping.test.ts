import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { mapPlaceOrderError } from './checkout_error_mapping.ts';

test('reserved cart quantity is returned as a retryable conflict', () => {
  assert.deepEqual(
    mapPlaceOrderError('CHECKOUT_QUANTITY_ALREADY_RESERVED'),
    { status: 409, code: 'CHECKOUT_QUANTITY_ALREADY_RESERVED' },
  );
});

test('unknown checkout failures do not expose database details', () => {
  assert.deepEqual(
    mapPlaceOrderError('internal database detail'),
    { status: 500, code: 'CHECKOUT_FAILED' },
  );
});
