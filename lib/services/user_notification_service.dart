import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_notification.dart';

abstract interface class UserNotificationRepository {
  Future<List<UserNotification>> getMyNotifications();
  Future<void> markRead(int notificationId);
}

class UserNotificationService implements UserNotificationRepository {
  UserNotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<UserNotification>> getMyNotifications() async {
    final rows = await _client
        .from('user_notifications')
        .select('id,event_type,entity_type,entity_id,created_at,read_at')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(100);
    return (rows as List)
        .map(
          (row) =>
              UserNotification.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markRead(int notificationId) async {
    await _client.rpc(
      'mark_my_user_notification_read',
      params: {'p_notification_id': notificationId},
    );
  }
}
