import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gocart/models/product.dart';
import 'package:gocart/providers/product_provider.dart';
import 'package:gocart/services/product_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeProductService extends ProductService {
  _FakeProductService()
    : super(
        supabaseClient: SupabaseClient('https://example.supabase.co', 'test'),
      );

  @override
  Future<List<Product>> getMyProducts(String expectedMerchantId) async {
    return [
      Product(
        id: 1,
        merchantId: expectedMerchantId,
        name: 'Product for $expectedMerchantId',
        description: '',
        originalPrice: 10,
        offerPrice: 9,
        stock: 1,
        category: 'Electronics',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ];
  }
}

class _PagedProductService extends ProductService {
  _PagedProductService()
    : super(
        supabaseClient: SupabaseClient('https://example.supabase.co', 'test'),
      );

  final products = List<Product>.generate(
    25,
    (index) => Product(
      id: index + 1,
      merchantId: 'merchant-a',
      name: 'Product ${index + 1}',
      description: '',
      originalPrice: 10,
      offerPrice: 9,
      stock: 1,
      category: 'Electronics',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );

  @override
  Future<List<Product>> getAllProducts({int offset = 0, int limit = 24}) async {
    return products.skip(offset).take(limit).toList();
  }
}

void main() {
  test('merchant product state is isolated per authenticated user', () async {
    final container = ProviderContainer(
      overrides: [
        productServiceProvider.overrideWithValue(_FakeProductService()),
      ],
    );
    addTearDown(container.dispose);

    final firstMerchantProducts = await container.read(
      myProductsProvider('merchant-a').future,
    );
    final secondMerchantProducts = await container.read(
      myProductsProvider('merchant-b').future,
    );

    expect(firstMerchantProducts.single.merchantId, 'merchant-a');
    expect(secondMerchantProducts.single.merchantId, 'merchant-b');
    expect(firstMerchantProducts.single.name, 'Product for merchant-a');
    expect(secondMerchantProducts.single.name, 'Product for merchant-b');
  });

  test(
    'buyer catalogue loads another page without losing the first page',
    () async {
      final container = ProviderContainer(
        overrides: [
          productServiceProvider.overrideWithValue(_PagedProductService()),
        ],
      );
      addTearDown(container.dispose);

      final firstPage = await container.read(productsProvider.future);
      expect(firstPage, hasLength(24));
      expect(container.read(productsProvider.notifier).hasMore, isTrue);

      await container.read(productsProvider.notifier).loadMoreProducts();

      expect(container.read(productsProvider).requireValue, hasLength(25));
      expect(
        container.read(productsProvider).requireValue.first.name,
        'Product 1',
      );
      expect(
        container.read(productsProvider).requireValue.last.name,
        'Product 25',
      );
      expect(container.read(productsProvider.notifier).hasMore, isFalse);
      expect(container.read(productsProvider.notifier).isLoadingMore, isFalse);
    },
  );
}
