import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gocart/models/demo_order.dart';
import 'package:gocart/screens/checkout_screen.dart';

void main() {
  test('demo order parses numeric totals and item snapshots', () {
    final order = DemoOrder.fromMap({
      'id': 'order-12345678',
      'status': 'placed',
      'payment_status': 'demo_paid',
      'total_amount': 129.5,
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

  test(
    'order display code safely handles IDs shorter than eight characters',
    () {
      final order = DemoOrder.fromMap({
        'id': 'ord-1',
        'total_amount': 10,
        'created_at': '2026-09-28T10:00:00Z',
        'order_items': const [],
      });

      expect(order.displayCode, 'ORD-1');
    },
  );

  test('order display code has a fallback for a missing ID', () {
    final order = DemoOrder.fromMap({
      'total_amount': 10,
      'created_at': '2026-09-28T10:00:00Z',
      'order_items': const [],
    });

    expect(order.displayCode, 'UNKNOWN');
  });

  test('order model tolerates nullable payment status and item list', () {
    final order = DemoOrder.fromMap({
      'id': 'order-2',
      'status': null,
      'payment_status': null,
      'total_amount': 0,
      'created_at': '2026-09-28T10:00:00Z',
      'order_items': null,
    });

    expect(order.status, 'pending');
    expect(order.paymentStatus, 'unpaid');
    expect(order.items, isEmpty);
  });

  test('malformed order snapshot fails into the screen error state', () {
    expect(
      () => DemoOrder.fromMap({
        'id': 'order-bad',
        'total_amount': 'not-a-number',
        'created_at': 'bad-date',
        'order_items': const [],
      }),
      throwsA(anything),
    );
  });

  test('demo order receipt accepts numeric RPC values', () {
    final receipt = DemoOrderReceipt.fromMap({
      'order_id': 'order-1',
      'total_amount': 42,
      'item_count': 3,
      'payment_status': 'unpaid',
    });

    expect(receipt.id, 'order-1');
    expect(receipt.total, 42);
    expect(receipt.itemCount, 3);
    expect(receipt.paymentStatus, 'unpaid');
  });

  testWidgets('demo order success does not claim payment succeeded', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DemoOrderSuccessScreen(
          receipt: DemoOrderReceipt(
            id: 'order-1',
            total: 42,
            paymentStatus: 'unpaid',
          ),
        ),
      ),
    );

    expect(find.text('Order created'), findsOneWidget);
    expect(
      find.text(
        'No real payment was taken. The database records this order as unpaid.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The demo payment succeeded. No real payment was taken.'),
      findsNothing,
    );
  });

  testWidgets('demo success reports a payment state confirmed by the database', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DemoOrderSuccessScreen(
          receipt: DemoOrderReceipt(
            id: 'order-1',
            total: 42,
            paymentStatus: 'paid',
          ),
        ),
      ),
    );

    expect(
      find.text(
        'No real payment was taken. The database records payment status as paid.',
      ),
      findsOneWidget,
    );
  });
}
