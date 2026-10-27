import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/services/order_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const buyerId = 'buyer-1';

  test(
    'retries only the legacy missing total_amount column as total',
    () async {
      final requestedColumns = <String>[];
      final requestedBuyerColumns = <String>[];
      final requestedBuyers = <String>[];
      final service = OrderService(
        currentUserId: () => buyerId,
        orderRowsLoader:
            ({
              required buyerId,
              required buyerColumn,
              required totalColumn,
            }) async {
              requestedColumns.add(totalColumn);
              requestedBuyerColumns.add(buyerColumn);
              requestedBuyers.add(buyerId);
              if (totalColumn == 'total_amount') {
                throw const PostgrestException(
                  message: 'column orders.total_amount does not exist',
                  code: '42703',
                );
              }
              if (buyerColumn == 'user_id') {
                throw const PostgrestException(
                  message: 'column orders.user_id does not exist',
                  code: '42703',
                );
              }
              return [
                {
                  'id': 'order-1',
                  'status': 'paid',
                  'payment_status': 'paid',
                  'total': 24.5,
                  'created_at': '2026-10-15T10:00:00Z',
                  'order_items': const [],
                },
              ];
            },
      );

      final orders = await service.getMyOrders(buyerId);

      expect(requestedColumns, ['total_amount', 'total', 'total']);
      expect(requestedBuyerColumns, ['user_id', 'user_id', 'buyer_id']);
      expect(requestedBuyers, [buyerId, buyerId, buyerId]);
      expect(orders.single.total, 24.5);
    },
  );

  test('does not retry unrelated PostgREST missing-column errors', () async {
    var calls = 0;
    final service = OrderService(
      currentUserId: () => buyerId,
      orderRowsLoader:
          ({
            required buyerId,
            required buyerColumn,
            required totalColumn,
          }) async {
            calls++;
            throw const PostgrestException(
              message: 'column orders.unknown_field does not exist',
              code: '42703',
            );
          },
    );

    await expectLater(
      service.getMyOrders(buyerId),
      throwsA(isA<PostgrestException>()),
    );
    expect(calls, 1);
  });

  test(
    'keeps order history queries scoped to the authenticated buyer',
    () async {
      var queried = false;
      final service = OrderService(
        currentUserId: () => 'buyer-1',
        orderRowsLoader:
            ({
              required buyerId,
              required buyerColumn,
              required totalColumn,
            }) async {
              queried = true;
              return const [];
            },
      );

      await expectLater(
        service.getMyOrders('buyer-2'),
        throwsA(isA<Exception>()),
      );
      expect(queried, isFalse);
    },
  );
}
