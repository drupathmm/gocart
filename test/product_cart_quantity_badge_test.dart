import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/widgets/product_cart_quantity_badge.dart';

void main() {
  testWidgets('product card quantity badge shows the current cart quantity', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductCartQuantityBadge(quantity: 3)),
      ),
    );

    expect(find.text('In cart: 3'), findsOneWidget);
  });

  testWidgets('quantity badge is hidden when the product is not in the cart', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductCartQuantityBadge(quantity: 0)),
      ),
    );

    expect(find.textContaining('In cart:'), findsNothing);
  });
}
