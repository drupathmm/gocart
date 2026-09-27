import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';
import '../services/cart_service.dart';
import 'auth_provider.dart';

final cartServiceProvider = Provider<CartService>((ref) {
  return CartService();
});

final cartProvider = AsyncNotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

class CartNotifier extends AsyncNotifier<List<CartItem>> {
  // Keeps track of cart items currently being updated.
  final Set<int> _updatingItemIds = {};

  @override
  Future<List<CartItem>> build() async {
    final authState = ref.watch(authUserIdProvider);
    final userId =
        authState.asData?.value ??
        Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return const [];
    }

    return ref.read(cartServiceProvider).getMyCart();
  }

  // ============================================================
  // REFRESH CART
  // ============================================================

  Future<void> refreshCart() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(cartServiceProvider).getMyCart(),
    );
  }

  // ============================================================
  // CHECK IF AN ITEM IS CURRENTLY UPDATING
  // ============================================================

  bool isItemUpdating(int cartItemId) {
    return _updatingItemIds.contains(cartItemId);
  }

  // ============================================================
  // ADD TO CART
  // ============================================================

  Future<void> addToCart({required int productId, int quantity = 1}) async {
    if (quantity <= 0) {
      throw Exception('Quantity must be greater than zero.');
    }

    await ref
        .read(cartServiceProvider)
        .addToCart(productId: productId, quantity: quantity);

    // We refresh here because a completely new cart item may have
    // been created and we need the product information from Supabase.
    await refreshCart();
  }

  // ============================================================
  // INCREASE QUANTITY
  // ============================================================

  Future<void> increaseQuantity(int cartItemId) async {
    final items = state.asData?.value;

    if (items == null) {
      await refreshCart();
      return;
    }

    CartItem? item;

    for (final cartItem in items) {
      if (cartItem.id == cartItemId) {
        item = cartItem;
        break;
      }
    }

    if (item == null) {
      return;
    }

    if (!item.canIncreaseQuantity) {
      throw Exception(
        'Only ${item.maxAvailableQuantity} item(s) are available.',
      );
    }

    if (_updatingItemIds.contains(cartItemId)) {
      return;
    }

    await updateQuantity(cartItemId: cartItemId, quantity: item.quantity + 1);
  }

  // ============================================================
  // DECREASE QUANTITY
  // ============================================================

  Future<void> decreaseQuantity(int cartItemId) async {
    final items = state.asData?.value;

    if (items == null) {
      await refreshCart();
      return;
    }

    CartItem? item;

    for (final cartItem in items) {
      if (cartItem.id == cartItemId) {
        item = cartItem;
        break;
      }
    }

    if (item == null) {
      return;
    }

    if (!item.canDecreaseQuantity) {
      return;
    }

    if (_updatingItemIds.contains(cartItemId)) {
      return;
    }

    await updateQuantity(cartItemId: cartItemId, quantity: item.quantity - 1);
  }

  // ============================================================
  // UPDATE QUANTITY WITHOUT RELOADING THE WHOLE CART
  // ============================================================

  Future<void> updateQuantity({
    required int cartItemId,
    required int quantity,
  }) async {
    if (_updatingItemIds.contains(cartItemId)) {
      return;
    }

    final currentItems = state.asData?.value;

    if (currentItems == null) {
      await refreshCart();
      return;
    }

    final itemIndex = currentItems.indexWhere((item) => item.id == cartItemId);

    if (itemIndex == -1) {
      return;
    }

    final oldItem = currentItems[itemIndex];

    // Quantity 0 means remove.
    if (quantity <= 0) {
      await removeFromCart(cartItemId);
      return;
    }

    // Never allow the local UI to exceed available stock.
    if (oldItem.product != null && quantity > oldItem.product!.stock) {
      throw Exception('Only ${oldItem.product!.stock} item(s) are available.');
    }

    _updatingItemIds.add(cartItemId);

    try {
      // ----------------------------------------------------------
      // 1. Update Supabase first
      // ----------------------------------------------------------

      await ref
          .read(cartServiceProvider)
          .updateQuantity(cartItemId: cartItemId, quantity: quantity);

      // ----------------------------------------------------------
      // 2. Update only this item locally
      // ----------------------------------------------------------

      final updatedItems = List<CartItem>.from(currentItems);

      updatedItems[itemIndex] = CartItem(
        id: oldItem.id,
        userId: oldItem.userId,
        productId: oldItem.productId,
        quantity: quantity,
        createdAt: oldItem.createdAt,
        product: oldItem.product,
      );

      // IMPORTANT:
      // We do NOT set AsyncLoading here.
      //
      // Therefore the cart remains visible while the quantity changes.
      state = AsyncData(updatedItems);
    } finally {
      _updatingItemIds.remove(cartItemId);
    }
  }

  // ============================================================
  // REMOVE FROM CART
  // ============================================================

  Future<void> removeFromCart(int cartItemId) async {
    final currentItems = state.asData?.value;

    if (currentItems == null) {
      await refreshCart();
      return;
    }

    final itemIndex = currentItems.indexWhere((item) => item.id == cartItemId);

    if (itemIndex == -1) {
      return;
    }

    if (_updatingItemIds.contains(cartItemId)) {
      return;
    }

    _updatingItemIds.add(cartItemId);

    try {
      await ref.read(cartServiceProvider).removeFromCart(cartItemId);

      // Remove only the deleted item from the current state.
      final updatedItems = List<CartItem>.from(currentItems)
        ..removeAt(itemIndex);

      state = AsyncData(updatedItems);
    } finally {
      _updatingItemIds.remove(cartItemId);
    }
  }

  // ============================================================
  // CLEAR CART
  // ============================================================

  Future<void> clearCart() async {
    await ref.read(cartServiceProvider).clearCart();

    // No need to reload from Supabase.
    // We already know the cart is empty.
    state = const AsyncData([]);
  }
}

// ================================================================
// CART ITEM COUNT
// ================================================================

final cartItemCountProvider = Provider<int>((ref) {
  final cartAsync = ref.watch(cartProvider);

  return cartAsync.maybeWhen(
    data: (items) {
      return items.fold<int>(0, (total, item) => total + item.quantity);
    },
    orElse: () => 0,
  );
});

// ================================================================
// CART TOTAL
// ================================================================

final cartTotalProvider = Provider<double>((ref) {
  final cartAsync = ref.watch(cartProvider);

  return cartAsync.maybeWhen(
    data: (items) {
      return items.fold<double>(0, (total, item) => total + item.totalPrice);
    },
    orElse: () => 0,
  );
});

// ================================================================
// ORIGINAL CART TOTAL
// ================================================================

final cartOriginalTotalProvider = Provider<double>((ref) {
  final cartAsync = ref.watch(cartProvider);

  return cartAsync.maybeWhen(
    data: (items) {
      return items.fold<double>(
        0,
        (total, item) => total + item.originalTotalPrice,
      );
    },
    orElse: () => 0,
  );
});

// ================================================================
// TOTAL SAVINGS
// ================================================================

final cartSavingsProvider = Provider<double>((ref) {
  final originalTotal = ref.watch(cartOriginalTotalProvider);
  final cartTotal = ref.watch(cartTotalProvider);

  final savings = originalTotal - cartTotal;

  return savings > 0 ? savings : 0;
});
