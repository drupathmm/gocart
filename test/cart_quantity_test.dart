import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/cart_item.dart';
import 'package:gocart/providers/cart_provider.dart';

void main() {
  test('product detail cart quantity reflects the current user cart rows', () {
    final items = [
      _item(id: 1, productId: 10, quantity: 2),
      _item(id: 2, productId: 10, quantity: 1),
      _item(id: 3, productId: 11, quantity: 4),
    ];

    expect(cartQuantityForProduct(items, 10), 3);
    expect(cartQuantityForProduct(items, 11), 4);
    expect(cartQuantityForProduct(items, 12), 0);
  });
}

CartItem _item({
  required int id,
  required int productId,
  required int quantity,
}) => CartItem(
  id: id,
  userId: 'buyer-1',
  productId: productId,
  quantity: quantity,
  createdAt: DateTime.utc(2026, 10, 15),
);
