import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/user_notification.dart';
import 'package:gocart/screens/user_notifications_screen.dart';
import 'package:gocart/services/user_notification_service.dart';

class _FakeNotificationService implements UserNotificationRepository {
  _FakeNotificationService(this.rows, {this.failuresRemaining = 0});

  List<UserNotification> rows;
  int failuresRemaining;
  int markReadCalls = 0;

  @override
  @override
  Future<List<UserNotification>> getMyNotifications() async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('synthetic load failure');
    }
    return List.of(rows);
  }

  @override
  @override
  Future<void> markRead(int notificationId) async {
    markReadCalls++;
    rows = rows.map((item) {
      if (item.id != notificationId) return item;
      return UserNotification(
        id: item.id,
        eventType: item.eventType,
        entityType: item.entityType,
        entityId: item.entityId,
        createdAt: item.createdAt,
        readAt: DateTime.utc(2026),
      );
    }).toList();
  }
}

UserNotification _notification(int id, {DateTime? readAt}) => UserNotification(
  id: id,
  eventType: 'payment_verified',
  entityType: 'payment',
  entityId: 'private-reference',
  createdAt: DateTime.utc(2026),
  readAt: readAt,
);

void main() {
  testWidgets('shows unread count and marks an item read', (tester) async {
    final service = _FakeNotificationService([_notification(1)]);
    await tester.pumpWidget(
      MaterialApp(home: UserNotificationsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 unread'), findsOneWidget);
    expect(find.text('Payment verified'), findsOneWidget);
    expect(find.text('private-reference'), findsNothing);

    await tester.tap(find.text('Payment verified'));
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 1);
    expect(find.text('0 unread'), findsOneWidget);
  });

  testWidgets('shows an empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserNotificationsScreen(
          service: _FakeNotificationService(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 unread'), findsOneWidget);
    expect(find.text('You are all caught up.'), findsOneWidget);
  });

  testWidgets('shows an error and retries loading', (tester) async {
    final service = _FakeNotificationService([
      _notification(2),
    ], failuresRemaining: 1);
    await tester.pumpWidget(
      MaterialApp(home: UserNotificationsScreen(service: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications are unavailable.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Payment verified'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);
  });
}
