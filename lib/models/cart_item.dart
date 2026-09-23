import 'product.dart';

class CartItem {
  final int id;
  final String userId;
  final int productId;
  final int quantity;
  final DateTime createdAt;
  final Product? product;

  const CartItem({
    required this.id,
    required this.userId,
    required this.productId,
    required this.quantity,
    required this.createdAt,
    this.product,
  });

  // --------------------------------------------------
  // Pricing
  // --------------------------------------------------

  /// Total amount for this cart item using the current
  /// offer price.
  double get totalPrice {
    if (product == null) {
      return 0;
    }

    return product!.offerPrice * quantity;
  }

  /// Original total before discount.
  double get originalTotalPrice {
    if (product == null) {
      return 0;
    }

    return product!.originalPrice * quantity;
  }

  /// Total amount saved on this cart item.
  double get totalSavings {
    final savings = originalTotalPrice - totalPrice;

    return savings > 0 ? savings : 0;
  }

  // --------------------------------------------------
  // Stock
  // --------------------------------------------------

  /// Maximum quantity that can currently be kept in
  /// the cart according to the product's stock.
  int get maxAvailableQuantity {
    if (product == null) {
      return 0;
    }

    return product!.stock;
  }

  /// Whether another unit can be added.
  bool get canIncreaseQuantity {
    return quantity < maxAvailableQuantity;
  }

  /// Whether the quantity can be reduced.
  bool get canDecreaseQuantity {
    return quantity > 1;
  }

  /// Whether this item is currently out of stock.
  bool get isOutOfStock {
    return product == null || product!.stock <= 0;
  }

  /// Whether the cart quantity is greater than the current
  /// available stock.
  ///
  /// This can happen if a merchant reduces stock after
  /// the buyer already added the product to their cart.
  bool get exceedsAvailableStock {
    if (product == null) {
      return false;
    }

    return quantity > product!.stock;
  }

  // --------------------------------------------------
  // Discount
  // --------------------------------------------------

  double get discountPercentage {
    if (product == null) {
      return 0;
    }

    return product!.discountPercentage;
  }

  // --------------------------------------------------
  // Supabase mapping
  // --------------------------------------------------

  factory CartItem.fromMap(Map<String, dynamic> map) {
    final productData = map['products'];

    return CartItem(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      productId: map['product_id'] as int,
      quantity: map['quantity'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      product: productData is Map<String, dynamic>
          ? Product.fromMap(productData)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {'user_id': userId, 'product_id': productId, 'quantity': quantity};
  }
}
