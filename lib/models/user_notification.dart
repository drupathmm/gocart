class UserNotification {
  const UserNotification({
    required this.id,
    required this.eventType,
    required this.entityType,
    required this.entityId,
    required this.createdAt,
    required this.readAt,
  });

  final int id;
  final String eventType;
  final String entityType;
  final String entityId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  String get title => switch (eventType) {
    'merchant_approved' => 'Merchant account approved',
    'merchant_suspended' => 'Merchant account suspended',
    'merchant_reinstated' => 'Merchant account reinstated',
    'reinstatement_requested' => 'Merchant review requested',
    'reinstatement_rejected' => 'Merchant review not approved',
    'order_placed' => 'Order placed',
    'order_received' => 'New order received',
    'order_status_changed' => 'Order status updated',
    'payment_verified' => 'Payment verified',
    _ => 'GoCart update',
  };

  String get message => switch (eventType) {
    'merchant_approved' => 'Your merchant account is approved.',
    'merchant_suspended' =>
      'Your merchant account is suspended. You can request a review.',
    'merchant_reinstated' => 'Your merchant account is active again.',
    'reinstatement_requested' => 'A merchant has requested an account review.',
    'reinstatement_rejected' =>
      'Your account review request was not approved. Check the review response in your merchant account.',
    'order_placed' => 'Your order was placed successfully.',
    'order_received' => 'A customer placed an order for your products.',
    'order_status_changed' => 'An order status has changed.',
    'payment_verified' => 'A payment was verified by GoCart.',
    _ => 'There is a new update in your GoCart account.',
  };

  factory UserNotification.fromMap(Map<String, dynamic> row) {
    final id = row['id'];
    final eventType = row['event_type'];
    final entityType = row['entity_type'];
    final entityId = row['entity_id'];
    final createdAt = row['created_at'];
    final readAt = row['read_at'];
    if (id is! num ||
        eventType is! String ||
        entityType is! String ||
        entityId is! String ||
        createdAt is! String ||
        (readAt != null && readAt is! String)) {
      throw const FormatException('Invalid notification response.');
    }
    return UserNotification(
      id: id.toInt(),
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      createdAt: DateTime.parse(createdAt).toUtc(),
      readAt: readAt == null ? null : DateTime.parse(readAt as String).toUtc(),
    );
  }
}
