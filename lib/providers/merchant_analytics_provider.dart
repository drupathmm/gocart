import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/merchant_analytics.dart';
import '../services/merchant_analytics_service.dart';

final merchantAnalyticsServiceProvider = Provider<MerchantAnalyticsService>(
  (ref) => MerchantAnalyticsService(),
);

final merchantAnalyticsProvider =
    FutureProvider.family<MerchantAnalytics, String>(
      (ref, merchantId) => ref
          .read(merchantAnalyticsServiceProvider)
          .loadForMerchant(merchantId),
    );
