import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cart_item.dart';
import '../services/cart_service.dart';

final cartServiceProvider = Provider<CartService>((ref) {
  return CartService();
});

final cartProvider = AsyncNotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

class CartNotifier extends AsyncNotifier<List<CartItem>> {
  @override
  Future<List<CartItem>> build() async {
    return ref.read(cartServiceProvider).getMyCart();
  }

  Future<void> refreshCart() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return ref.read(cartServiceProvider).getMyCart();
    });
  }

  Future<void> addToCart({required int productId, int quantity = 1}) async {
    await ref
        .read(cartServiceProvider)
        .addToCart(productId: productId, quantity: quantity);

    await refreshCart();
  }

  Future<void> updateQuantity({
    required int cartItemId,
    required int quantity,
  }) async {
    await ref
        .read(cartServiceProvider)
        .updateQuantity(cartItemId: cartItemId, quantity: quantity);

    await refreshCart();
  }

  Future<void> removeFromCart(int cartItemId) async {
    await ref.read(cartServiceProvider).removeFromCart(cartItemId);

    await refreshCart();
  }

  Future<void> clearCart() async {
    await ref.read(cartServiceProvider).clearCart();

    await refreshCart();
  }
}

final cartItemCountProvider = Provider<int>((ref) {
  final cartAsync = ref.watch(cartProvider);

  return cartAsync.maybeWhen(
    data: (items) {
      return items.fold<int>(0, (total, item) => total + item.quantity);
    },
    orElse: () => 0,
  );
});

final cartTotalProvider = Provider<double>((ref) {
  final cartAsync = ref.watch(cartProvider);

  return cartAsync.maybeWhen(
    data: (items) {
      return items.fold<double>(0, (total, item) => total + item.totalPrice);
    },
    orElse: () => 0,
  );
});
