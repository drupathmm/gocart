import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/user_notification.dart';

void main() {
  test('parses a payment event without exposing arbitrary server text', () {
    final notification = UserNotification.fromMap({
      'id': 12,
      'event_type': 'payment_verified',
      'entity_type': 'payment',
      'entity_id': 'provider-payment-id',
      'created_at': '2026-10-27T09:30:00Z',
      'read_at': null,
    });

    expect(notification.title, 'Payment verified');
    expect(notification.message, 'A payment was verified by GoCart.');
    expect(notification.isRead, isFalse);
  });

  test('maps merchant and order lifecycle events to safe user copy', () {
    for (final event in [
      'merchant_approved',
      'merchant_suspended',
      'merchant_reinstated',
      'reinstatement_requested',
      'reinstatement_rejected',
      'order_placed',
      'order_received',
      'order_status_changed',
    ]) {
      final notification = UserNotification.fromMap({
        'id': 1,
        'event_type': event,
        'entity_type': 'order',
        'entity_id': 'internal-reference',
        'created_at': '2026-10-27T09:30:00Z',
        'read_at': '2026-10-27T09:31:00Z',
      });
      expect(notification.title, isNotEmpty);
      expect(notification.message, isNotEmpty);
      expect(notification.message, isNot(contains('internal-reference')));
      expect(notification.isRead, isTrue);
    }
  });

  test('rejects malformed notification responses', () {
    expect(() => UserNotification.fromMap(const {}), throwsFormatException);
  });
}
