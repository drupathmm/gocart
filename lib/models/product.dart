class Product {
  final int id;
  final String merchantId;
  final String name;
  final String description;
  final double originalPrice;
  final double offerPrice;
  final int stock;
  final String category;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.description,
    required this.originalPrice,
    required this.offerPrice,
    required this.stock,
    required this.category,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns the discount percentage.
  ///
  /// Example:
  /// original price = 1000
  /// offer price = 800
  /// discount = 20%
  double get discountPercentage {
    if (originalPrice <= 0 || offerPrice >= originalPrice) {
      return 0;
    }

    return ((originalPrice - offerPrice) / originalPrice) * 100;
  }

  /// Whether this product currently has an offer.
  bool get hasDiscount {
    return offerPrice < originalPrice;
  }

  /// Whether the product is completely out of stock.
  bool get isOutOfStock {
    return stock <= 0;
  }

  /// Whether the product has low stock.
  bool get isLowStock {
    return stock > 0 && stock <= 5;
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      merchantId: map['merchant_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      originalPrice: (map['original_price'] as num).toDouble(),
      offerPrice: (map['offer_price'] as num).toDouble(),
      stock: map['stock'] as int,
      category: map['category'] as String,
      imageUrl: map['image_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchant_id': merchantId,
      'name': name,
      'description': description,
      'original_price': originalPrice,
      'offer_price': offerPrice,
      'stock': stock,
      'category': category,
      'image_url': imageUrl,
    };
  }
}
