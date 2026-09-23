import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../services/product_service.dart';

// --------------------------------------------------
// Product Service
// --------------------------------------------------

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService();
});

// --------------------------------------------------
// All Products
// Used by buyers
// --------------------------------------------------

final productsProvider = AsyncNotifierProvider<ProductsNotifier, List<Product>>(
  ProductsNotifier.new,
);

class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return ref.read(productServiceProvider).getAllProducts();
  }

  // --------------------------------------------------
  // Refresh all products
  // --------------------------------------------------

  Future<void> refreshProducts() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getAllProducts(),
    );
  }

  // --------------------------------------------------
  // Search products
  // --------------------------------------------------

  Future<void> search(String searchText) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(productServiceProvider).searchProducts(searchText),
    );
  }

  // --------------------------------------------------
  // Filter products by category
  // --------------------------------------------------

  Future<void> filterByCategory(String category) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getProductsByCategory(category),
    );
  }

  // --------------------------------------------------
  // Reset to all products
  // --------------------------------------------------

  Future<void> clearFilters() async {
    await refreshProducts();
  }
}

// --------------------------------------------------
// My Products
// Used by merchants
// --------------------------------------------------

final myProductsProvider =
    AsyncNotifierProvider<MyProductsNotifier, List<Product>>(
      MyProductsNotifier.new,
    );

class MyProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return ref.read(productServiceProvider).getMyProducts();
  }

  // --------------------------------------------------
  // Refresh merchant products
  // --------------------------------------------------

  Future<void> refreshProducts() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getMyProducts(),
    );
  }

  // --------------------------------------------------
  // Add Product
  // --------------------------------------------------

  Future<void> addProduct({
    required String name,
    required String description,
    required double originalPrice,
    required double offerPrice,
    required int stock,
    required String category,
    XFile? imageFile,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.createProduct(
      name: name,
      description: description,
      originalPrice: originalPrice,
      offerPrice: offerPrice,
      stock: stock,
      category: category,
      imageFile: imageFile,
    );

    await refreshProducts();
  }

  // --------------------------------------------------
  // Update Product
  // --------------------------------------------------

  Future<void> updateProduct({
    required int productId,
    required String name,
    required String description,
    required double originalPrice,
    required double offerPrice,
    required int stock,
    required String category,
    XFile? imageFile,
    bool removeImage = false,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.updateProduct(
      productId: productId,
      name: name,
      description: description,
      originalPrice: originalPrice,
      offerPrice: offerPrice,
      stock: stock,
      category: category,
      imageFile: imageFile,
      removeImage: removeImage,
    );

    await refreshProducts();
  }

  // --------------------------------------------------
  // Delete Product
  // --------------------------------------------------

  Future<void> deleteProduct(int productId) async {
    final service = ref.read(productServiceProvider);

    await service.deleteProduct(productId);

    await refreshProducts();
  }
}
