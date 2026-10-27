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

/// Resolves merchant restrictions from the persisted profile, never from
/// client metadata. The dashboard uses this to disable selling tools while
/// retaining the authenticated session for pending and suspended merchants.
final merchantStatusProvider = FutureProvider.family<String?, String>((
  ref,
  merchantId,
) async {
  final profile = await Supabase.instance.client
      .from('profiles')
      .select('role, merchant_status')
      .eq('id', merchantId)
      .maybeSingle();
  if (profile == null || profile['role'] != 'merchant') return null;
  return profile['merchant_status'] as String?;
});
