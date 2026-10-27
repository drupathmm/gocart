import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/razorpay_checkout.dart';

void main() {
  group('Razorpay server response validation', () {
    test('accepts a test order returned by the server', () {
      final order = RazorpayOrderDetails.fromMap({
        'order_id': 'local-order',
        'razorpay_order_id': 'provider-order',
        'razorpay_key_id': 'rzp_test_public_id',
        'amount': 12500,
        'currency': 'INR',
      });

      expect(order.amountPaise, 12500);
      expect(order.currency, 'INR');
    });

    test('rejects a live key, invalid amount, or currency', () {
      for (final changes in [
        {'razorpay_key_id': 'rzp_live_id'},
        {'amount': 0},
        {'currency': 'USD'},
      ]) {
        expect(
          () => RazorpayOrderDetails.fromMap({
            'order_id': 'local-order',
            'razorpay_order_id': 'provider-order',
            'razorpay_key_id': 'rzp_test_public_id',
            'amount': 12500,
            'currency': 'INR',
            ...changes,
          }),
          throwsFormatException,
        );
      }
    });

    test(
      'paid state requires confirmation in both order and payment fields',
      () {
        final pending = RazorpayVerificationResult.fromMap({
          'order_id': 'local-order',
          'status': 'pending',
          'payment_status': 'unpaid',
          'verification_result': 'review_required',
        });
        final paid = RazorpayVerificationResult.fromMap({
          'order_id': 'local-order',
          'status': 'paid',
          'payment_status': 'paid',
          'verification_result': 'captured',
        });

        expect(pending.isPaid, isFalse);
        expect(paid.isPaid, isTrue);
      },
    );
  });
}
