import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/demo_order.dart';

class OrderService {
  final SupabaseClient _supabase;

  OrderService({SupabaseClient? supabaseClient})
    : _supabase = supabaseClient ?? Supabase.instance.client;

  void _requireExpectedBuyer(String expectedBuyerId) {
    final user = _supabase.auth.currentUser;
    if (user == null || user.id != expectedBuyerId) {
      throw Exception('Your session changed. Please sign in again.');
    }
  }

  Future<DemoOrderReceipt> placeDemoOrder(String expectedBuyerId) async {
    _requireExpectedBuyer(expectedBuyerId);
    final response = await _supabase.rpc('place_demo_order');

    if (response is! Map) {
      throw Exception('The demo order could not be confirmed.');
    }

    return DemoOrderReceipt.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<DemoOrder>> getMyOrders(String expectedBuyerId) async {
    _requireExpectedBuyer(expectedBuyerId);

    final response = await _supabase
        .from('orders')
        .select(
          'id, status, payment_status, total, created_at, '
          'order_items(product_name, unit_price, quantity, line_total)',
        )
        .eq('buyer_id', expectedBuyerId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => DemoOrder.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
