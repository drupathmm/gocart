import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/demo_order.dart';

void main() {
  test('demo order parses numeric totals and item snapshots', () {
    final order = DemoOrder.fromMap({
      'id': 'order-12345678',
      'status': 'placed',
      'payment_status': 'demo_paid',
      'total': 129.5,
      'created_at': '2026-09-28T10:00:00Z',
      'order_items': [
        {
          'product_name': 'Travel mug',
          'unit_price': 64.75,
          'quantity': 2,
          'line_total': 129.5,
        },
      ],
    });

    expect(order.id, 'order-12345678');
    expect(order.total, 129.5);
    expect(order.items.single.productName, 'Travel mug');
    expect(order.items.single.quantity, 2);
    expect(order.items.single.lineTotal, 129.5);
  });

  test('demo order receipt accepts numeric RPC values', () {
    final receipt = DemoOrderReceipt.fromMap({
      'order_id': 'order-1',
      'total': 42,
      'item_count': 3,
    });

    expect(receipt.id, 'order-1');
    expect(receipt.total, 42);
    expect(receipt.itemCount, 3);
  });
}
