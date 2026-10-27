import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/navigation/cart_navigation.dart';

void main() {
  testWidgets('view cart navigation pushes the cart destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => navigateToCart(
                context,
                cartBuilder: (_) => const Scaffold(body: Text('Cart screen')),
              ),
              child: const Text('View cart'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('View cart'));
    await tester.pumpAndSettle();
    expect(find.text('Cart screen'), findsOneWidget);
  });
}
