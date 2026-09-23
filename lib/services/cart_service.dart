import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';

class CartService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // --------------------------------------------------
  // Current user
  // --------------------------------------------------

  String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    return user.id;
  }

  // --------------------------------------------------
  // Get my cart
  // --------------------------------------------------

  Future<List<CartItem>> getMyCart() async {
    final userId = _requireUserId();

    final response = await _supabase
        .from('cart_items')
        .select('''
          id,
          user_id,
          product_id,
          quantity,
          created_at,
          products (
            id,
            merchant_id,
            name,
            description,
            original_price,
            offer_price,
            price,
            stock,
            category,
            image_url,
            created_at,
            updated_at
          )
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => CartItem.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  // --------------------------------------------------
  // Add to cart
  //
  // Stock validation is performed atomically inside
  // PostgreSQL through the add_to_cart RPC.
  // --------------------------------------------------

  Future<void> addToCart({required int productId, int quantity = 1}) async {
    _requireUserId();

    if (quantity <= 0) {
      throw Exception('Quantity must be greater than zero.');
    }

    await _supabase.rpc(
      'add_to_cart',
      params: {'p_product_id': productId, 'p_quantity': quantity},
    );
  }

  // --------------------------------------------------
  // Update cart quantity
  //
  // Stock validation is performed atomically inside
  // PostgreSQL through the update_cart_quantity RPC.
  // --------------------------------------------------

  Future<void> updateQuantity({
    required int cartItemId,
    required int quantity,
  }) async {
    _requireUserId();

    if (quantity <= 0) {
      await removeFromCart(cartItemId);
      return;
    }

    await _supabase.rpc(
      'update_cart_quantity',
      params: {'p_cart_item_id': cartItemId, 'p_quantity': quantity},
    );
  }

  // --------------------------------------------------
  // Remove cart item
  // --------------------------------------------------

  Future<void> removeFromCart(int cartItemId) async {
    final userId = _requireUserId();

    await _supabase
        .from('cart_items')
        .delete()
        .eq('id', cartItemId)
        .eq('user_id', userId);
  }

  // --------------------------------------------------
  // Clear entire cart
  // --------------------------------------------------

  Future<void> clearCart() async {
    final userId = _requireUserId();

    await _supabase.from('cart_items').delete().eq('user_id', userId);
  }
}
