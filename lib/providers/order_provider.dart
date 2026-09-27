import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/demo_order.dart';
import '../services/order_service.dart';

final orderServiceProvider = Provider<OrderService>((ref) => OrderService());

final myOrdersProvider = FutureProvider.autoDispose
    .family<List<DemoOrder>, String>((ref, buyerId) {
      return ref.read(orderServiceProvider).getMyOrders(buyerId);
    });
