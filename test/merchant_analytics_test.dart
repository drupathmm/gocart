import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/merchant_analytics.dart';

void main() {
  test(
    'parses server-scoped paid sales, trend, products, and recent orders',
    () {
      final analytics = MerchantAnalytics.fromResponse({
        'currency': 'INR',
        'paid_item_sales': 1499.5,
        'total_orders': 2,
        'pending_orders': 1,
        'completed_orders': 1,
        'sales_trend': [
          {'date': '2026-10-15', 'amount': 1499.5},
        ],
        'top_products': [
          {
            'product_id': 5,
            'product_name': 'Canvas bag',
            'quantity': 3,
            'sales': 1499.5,
          },
        ],
        'recent_orders': [
          {
            'order_id': 'order-1',
            'status': 'delivered',
            'created_at': '2026-10-15T09:30:00Z',
            'paid_item_sales': 1499.5,
            'item_quantity': 3,
          },
        ],
      });

      expect(analytics.currency, 'INR');
      expect(analytics.paidItemSales, 1499.5);
      expect(analytics.totalOrders, 2);
      expect(analytics.pendingOrders, 1);
      expect(analytics.completedOrders, 1);
      expect(analytics.salesTrend.single.amount, 1499.5);
      expect(analytics.topProducts.single.quantity, 3);
      expect(analytics.recentOrders.single.id, 'order-1');
    },
  );

  test('parses a valid empty analytics result without inventing sales', () {
    final analytics = MerchantAnalytics.fromResponse({
      'currency': 'INR',
      'paid_item_sales': 0,
      'total_orders': 0,
      'pending_orders': 0,
      'completed_orders': 0,
      'sales_trend': [],
      'top_products': [],
      'recent_orders': [],
    });

    expect(analytics.isEmpty, isTrue);
    expect(analytics.paidItemSales, 0);
    expect(analytics.recentOrders, isEmpty);
  });

  test('rejects a non-object analytics response', () {
    expect(
      () => MerchantAnalytics.fromResponse(const []),
      throwsA(isA<FormatException>()),
    );
  });
}
