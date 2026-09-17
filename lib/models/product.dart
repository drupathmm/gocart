class Product {
  final int id;
  final String merchantId;
  final String name;
  final String description;
  final double price;
  final int stock;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.description,
    required this.price,
    required this.stock,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int,
      merchantId: map['merchant_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      price: (map['price'] as num).toDouble(),
      stock: map['stock'] as int,
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
      'price': price,
      'stock': stock,
      'image_url': imageUrl,
    };
  }
}
