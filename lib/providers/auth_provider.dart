import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emits the authenticated user id whenever Supabase changes accounts.
/// Account-scoped providers can watch this to avoid retaining one user's
/// private app state after sign-in, sign-out, or account switching.
final authUserIdProvider = StreamProvider<String?>((ref) {
  final auth = Supabase.instance.client.auth;
  return auth.onAuthStateChange
      .map((state) => state.session?.user.id)
      .distinct();
});
