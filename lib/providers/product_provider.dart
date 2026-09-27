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
  int _requestVersion = 0;

  @override
  Future<List<Product>> build() async {
    final requestVersion = _requestVersion;
    final products = await ref.read(productServiceProvider).getAllProducts();
    if (requestVersion != _requestVersion) {
      return state.asData?.value ?? const <Product>[];
    }
    return products;
  }

  // --------------------------------------------------
  // Refresh all products
  // --------------------------------------------------

  Future<void> refreshProducts() async {
    final requestVersion = ++_requestVersion;
    state = const AsyncLoading();

    final result = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getAllProducts(),
    );
    if (requestVersion == _requestVersion) {
      state = result;
    }
  }

  // --------------------------------------------------
  // Search products
  // --------------------------------------------------

  Future<void> search(String searchText) async {
    final requestVersion = ++_requestVersion;
    state = const AsyncLoading();

    final result = await AsyncValue.guard(
      () => ref.read(productServiceProvider).searchProducts(searchText),
    );
    if (requestVersion == _requestVersion) {
      state = result;
    }
  }

  // --------------------------------------------------
  // Filter products by category
  // --------------------------------------------------

  Future<void> filterByCategory(String category) async {
    final requestVersion = ++_requestVersion;
    state = const AsyncLoading();

    final result = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getProductsByCategory(category),
    );
    if (requestVersion == _requestVersion) {
      state = result;
    }
  }

  /// Invalidates an in-flight search as soon as the user edits the query,
  /// including during the UI debounce interval.
  void cancelPendingRequests() {
    _requestVersion++;
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

// Merchant data is keyed by the authenticated user id. A single global
// notifier can otherwise keep the previous merchant's dashboard cached when
// the active account changes without recreating ProviderScope.
final myProductsProvider =
    AsyncNotifierProvider.family<MyProductsNotifier, List<Product>, String>(
      MyProductsNotifier.new,
    );

class MyProductsNotifier extends AsyncNotifier<List<Product>> {
  MyProductsNotifier(this._merchantId);

  final String _merchantId;

  @override
  Future<List<Product>> build() async {
    return ref.read(productServiceProvider).getMyProducts(_merchantId);
  }

  // --------------------------------------------------
  // Refresh merchant products
  // --------------------------------------------------

  Future<void> refreshProducts() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(
      () => ref.read(productServiceProvider).getMyProducts(_merchantId),
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
      expectedMerchantId: _merchantId,
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
      expectedMerchantId: _merchantId,
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

    await service.deleteProduct(productId, expectedMerchantId: _merchantId);

    await refreshProducts();
  }
}
