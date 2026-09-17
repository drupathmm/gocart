import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../services/product_service.dart';

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

  Future<void> refreshProducts() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return ref.read(productServiceProvider).getAllProducts();
    });
  }

  Future<void> search(String searchText) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return ref.read(productServiceProvider).searchProducts(searchText);
    });
  }

  Future<void> addProduct({
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.createProduct(
      name: name,
      description: description,
      price: price,
      stock: stock,
      imageUrl: imageUrl,
    );

    await refreshProducts();
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.updateProduct(
      productId: productId,
      name: name,
      description: description,
      price: price,
      stock: stock,
      imageUrl: imageUrl,
    );

    await refreshProducts();
  }

  Future<void> deleteProduct(int productId) async {
    final service = ref.read(productServiceProvider);

    await service.deleteProduct(productId);

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

  Future<void> refreshProducts() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() {
      return ref.read(productServiceProvider).getMyProducts();
    });
  }

  Future<void> addProduct({
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.createProduct(
      name: name,
      description: description,
      price: price,
      stock: stock,
      imageUrl: imageUrl,
    );

    await refreshProducts();
  }

  Future<void> updateProduct({
    required int productId,
    required String name,
    required String description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final service = ref.read(productServiceProvider);

    await service.updateProduct(
      productId: productId,
      name: name,
      description: description,
      price: price,
      stock: stock,
      imageUrl: imageUrl,
    );

    await refreshProducts();
  }

  Future<void> deleteProduct(int productId) async {
    final service = ref.read(productServiceProvider);

    await service.deleteProduct(productId);

    await refreshProducts();
  }
}
