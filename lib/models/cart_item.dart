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

  double get totalPrice {
    if (product == null) {
      return 0;
    }

    return product!.price * quantity;
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      id: map['id'] as int,
      userId: map['user_id'] as String,
      productId: map['product_id'] as int,
      quantity: map['quantity'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      product: map['products'] != null
          ? Product.fromMap(map['products'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {'user_id': userId, 'product_id': productId, 'quantity': quantity};
  }
}
