import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/merchant_analytics.dart';

class MerchantAnalyticsService {
  MerchantAnalyticsService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<MerchantAnalytics> loadForMerchant(String expectedMerchantId) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null || currentUser.id != expectedMerchantId) {
      throw const FormatException(
        'Sign in as this merchant to view analytics.',
      );
    }

    final response = await _supabase
        .rpc('merchant_sales_analytics')
        .timeout(const Duration(seconds: 20));
    return MerchantAnalytics.fromResponse(response);
  }
}
