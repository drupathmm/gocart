import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cart_item.dart';

class CartService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<CartItem>> getMyCart() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

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
            price,
            stock,
            image_url,
            created_at,
            updated_at
          )
        ''')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => CartItem.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> addToCart({required int productId, int quantity = 1}) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final existing = await _supabase
        .from('cart_items')
        .select('id, quantity')
        .eq('user_id', user.id)
        .eq('product_id', productId)
        .maybeSingle();

    if (existing != null) {
      final currentQuantity = existing['quantity'] as int;

      await _supabase
          .from('cart_items')
          .update({'quantity': currentQuantity + quantity})
          .eq('id', existing['id']);
    } else {
      await _supabase.from('cart_items').insert({
        'user_id': user.id,
        'product_id': productId,
        'quantity': quantity,
      });
    }
  }

  Future<void> updateQuantity({
    required int cartItemId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      await removeFromCart(cartItemId);
      return;
    }

    await _supabase
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', cartItemId);
  }

  Future<void> removeFromCart(int cartItemId) async {
    await _supabase.from('cart_items').delete().eq('id', cartItemId);
  }

  Future<void> clearCart() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    await _supabase.from('cart_items').delete().eq('user_id', user.id);
  }
}
