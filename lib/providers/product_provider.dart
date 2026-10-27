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
  static const int _pageSize = 24;
  int _requestVersion = 0;
  int _nextOffset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String? _loadMoreError;
  Future<List<Product>> Function(int offset, int limit)? _loadPage;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get loadMoreError => _loadMoreError;

  @override
  Future<List<Product>> build() async {
    final requestVersion = _requestVersion;
    final service = ref.read(productServiceProvider);
    _loadPage = (offset, limit) =>
        service.getAllProducts(offset: offset, limit: limit);
    final products = await _loadPage!(0, _pageSize);
    if (requestVersion != _requestVersion) {
      return state.asData?.value ?? const <Product>[];
    }
    _nextOffset = products.length;
    _hasMore = products.length == _pageSize;
    return products;
  }

  // --------------------------------------------------
  // Refresh all products
  // --------------------------------------------------

  Future<void> refreshProducts() async {
    final service = ref.read(productServiceProvider);
    await _loadFirstPage(
      (offset, limit) => service.getAllProducts(offset: offset, limit: limit),
    );
  }

  // --------------------------------------------------
  // Search products
  // --------------------------------------------------

  Future<void> search(String searchText) async {
    final service = ref.read(productServiceProvider);
    await _loadFirstPage(
      (offset, limit) =>
          service.searchProducts(searchText, offset: offset, limit: limit),
    );
  }

  // --------------------------------------------------
  // Filter products by category
  // --------------------------------------------------

  Future<void> filterByCategory(String category) async {
    final service = ref.read(productServiceProvider);
    await _loadFirstPage(
      (offset, limit) =>
          service.getProductsByCategory(category, offset: offset, limit: limit),
    );
  }

  Future<void> _loadFirstPage(
    Future<List<Product>> Function(int offset, int limit) loader,
  ) async {
    final requestVersion = ++_requestVersion;
    _loadPage = loader;
    _nextOffset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    _loadMoreError = null;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => loader(0, _pageSize));
    if (requestVersion != _requestVersion) return;
    if (result case AsyncData(:final value)) {
      _nextOffset = value.length;
      _hasMore = value.length == _pageSize;
    }
    state = result;
  }

  Future<void> loadMoreProducts() async {
    final current = state.asData?.value;
    final loader = _loadPage;
    if (current == null || !_hasMore || _isLoadingMore || loader == null) {
      return;
    }

    final requestVersion = _requestVersion;
    _isLoadingMore = true;
    _loadMoreError = null;
    state = AsyncData(List<Product>.of(current));
    try {
      final nextPage = await loader(_nextOffset, _pageSize);
      if (requestVersion != _requestVersion) return;
      _nextOffset += nextPage.length;
      _hasMore = nextPage.length == _pageSize;
      state = AsyncData([...current, ...nextPage]);
    } catch (_) {
      if (requestVersion == _requestVersion) {
        _loadMoreError = 'Could not load more products. Try again.';
        state = AsyncData(List<Product>.of(current));
      }
    } finally {
      if (requestVersion == _requestVersion) {
        _isLoadingMore = false;
        final latest = state.asData?.value;
        if (latest != null) state = AsyncData(List<Product>.of(latest));
      }
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
