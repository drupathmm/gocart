import 'package:flutter/material.dart';

import '../screens/cart_screen.dart';

void navigateToCart(BuildContext context, {WidgetBuilder? cartBuilder}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: cartBuilder ?? (_) => const CartScreen()),
  );
}
