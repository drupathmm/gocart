class DemoOrderReceipt {
  final String id;
  final double total;
  final int itemCount;

  const DemoOrderReceipt({
    required this.id,
    required this.total,
    required this.itemCount,
  });

  factory DemoOrderReceipt.fromMap(Map<String, dynamic> map) {
    return DemoOrderReceipt(
      id: map['order_id'].toString(),
      total: (map['total'] as num).toDouble(),
      itemCount: (map['item_count'] as num).toInt(),
    );
  }
}

class DemoOrder {
  final String id;
  final String status;
  final String paymentStatus;
  final double total;
  final DateTime createdAt;
  final List<DemoOrderItem> items;

  const DemoOrder({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.total,
    required this.createdAt,
    required this.items,
  });

  factory DemoOrder.fromMap(Map<String, dynamic> map) {
    final rawItems = map['order_items'] as List<dynamic>? ?? const [];
    return DemoOrder(
      id: map['id'].toString(),
      status: map['status'] as String? ?? 'placed',
      paymentStatus: map['payment_status'] as String? ?? 'demo_paid',
      total: (map['total'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      items: rawItems
          .map((item) => DemoOrderItem.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DemoOrderItem {
  final String productName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  const DemoOrderItem({
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  factory DemoOrderItem.fromMap(Map<String, dynamic> map) {
    return DemoOrderItem(
      productName: map['product_name'] as String? ?? 'Product',
      unitPrice: (map['unit_price'] as num).toDouble(),
      quantity: (map['quantity'] as num).toInt(),
      lineTotal: (map['line_total'] as num).toDouble(),
    );
  }
}
