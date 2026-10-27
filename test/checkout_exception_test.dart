import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/checkout_exception.dart';

void main() {
  test('maps server checkout codes to buyer-facing copy', () {
    expect(
      CheckoutException.fromCode('OUT_OF_STOCK').message,
      contains('out of stock'),
    );
    expect(CheckoutException.fromCode('CART_EMPTY').message, contains('empty'));
    expect(
      CheckoutException.fromCode('OFFER_NOT_AVAILABLE').message,
      contains('offer'),
    );
    expect(
      CheckoutException.fromCode('MERCHANT_UNAVAILABLE').message,
      contains('store'),
    );
    expect(
      CheckoutException.fromCode('IDEMPOTENCY_CONFLICT').message,
      contains('earlier request'),
    );
    expect(
      CheckoutException.fromCode('CHECKOUT_QUANTITY_ALREADY_RESERVED').message,
      contains('already being checked out'),
    );
  });
}
