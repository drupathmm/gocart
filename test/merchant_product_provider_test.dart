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
}
