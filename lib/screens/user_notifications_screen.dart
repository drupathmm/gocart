import 'package:flutter/material.dart';

import '../models/user_notification.dart';
import '../services/user_notification_service.dart';
import '../theme/app_theme.dart';

class UserNotificationsScreen extends StatefulWidget {
  const UserNotificationsScreen({
    super.key,
    UserNotificationRepository? service,
  }) : _service = service;

  final UserNotificationRepository? _service;

  @override
  State<UserNotificationsScreen> createState() =>
      _UserNotificationsScreenState();
}

class _UserNotificationsScreenState extends State<UserNotificationsScreen> {
  late final UserNotificationRepository _service =
      widget._service ?? UserNotificationService();
  late Future<List<UserNotification>> _load = _service.getMyNotifications();

  Future<void> _refresh() async {
    final future = _service.getMyNotifications();
    setState(() {
      _load = future;
    });
    // FutureBuilder renders the failure state; consume it here as well so a
    // failed pull-to-refresh does not escape as an unhandled async error.
    try {
      await future;
    } catch (_) {
      // The same failed future remains attached to FutureBuilder for display.
    }
  }

  Future<void> _markRead(UserNotification notification) async {
    if (notification.isRead) return;
    try {
      await _service.markRead(notification.id);
      if (mounted) await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this notification.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoCartTheme.canvas,
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder<List<UserNotification>>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Notifications are unavailable.'),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          final notifications = snapshot.data ?? const [];
          final unreadCount = notifications
              .where((item) => !item.isRead)
              .length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('$unreadCount unread'),
                ),
              ),
              Expanded(
                child: notifications.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 150),
                            Icon(Icons.notifications_none_rounded, size: 48),
                            SizedBox(height: 12),
                            Center(child: Text('You are all caught up.')),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: notifications.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final notification = notifications[index];
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  notification.isRead
                                      ? Icons.notifications_none_rounded
                                      : Icons.notifications_active_rounded,
                                ),
                                title: Text(notification.title),
                                subtitle: Text(notification.message),
                                trailing: notification.isRead
                                    ? null
                                    : const Icon(Icons.circle, size: 9),
                                onTap: () => _markRead(notification),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
