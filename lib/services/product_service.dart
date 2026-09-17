import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get all products
  Future<List<Product>> getAllProducts() async {
    final response = await _supabase
        .from('products')
        .select()
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => Product.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  // Get products belonging to the logged-in merchant
  Future<List<Product>> getMyProducts() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final response = await _supabase
        .from('products')
        .select()
        .eq('merchant_id', user.id)
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => Product.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  // Get a single product
  Future<Product> getProductById(int productId) async {
    final response = await _supabase
        .from('products')
        .select()
        .eq('id', productId)
        .single();

    return Product.fromMap(response);
  }

  // Add a new product
  Future<Product> createProduct({
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final response = await _supabase
        .from('products')
        .insert({
          'merchant_id': user.id,
          'name': name,
          'description': description,
          'price': price,
          'stock': stock,
          'image_url': imageUrl,
        })
        .select()
        .single();

    return Product.fromMap(response);
  }

  // Update an existing product
  Future<Product> updateProduct({
    required int productId,
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final response = await _supabase
        .from('products')
        .update({
          'name': name,
          'description': description,
          'price': price,
          'stock': stock,
          'image_url': imageUrl,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', productId)
        .select()
        .single();

    return Product.fromMap(response);
  }

  // Delete a product
  Future<void> deleteProduct(int productId) async {
    await _supabase.from('products').delete().eq('id', productId);
  }

  // Search products
  Future<List<Product>> searchProducts(String searchText) async {
    final query = searchText.trim();

    if (query.isEmpty) {
      return getAllProducts();
    }

    final response = await _supabase
        .from('products')
        .select()
        .or('name.ilike.%$query%,description.ilike.%$query%')
        .order('created_at', ascending: false);

    return (response as List)
        .map((item) => Product.fromMap(item as Map<String, dynamic>))
        .toList();
  }
}
