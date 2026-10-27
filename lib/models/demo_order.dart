class DemoOrderReceipt {
  final String id;
  final double total;
  final int itemCount;
  final String? paymentStatus;

  const DemoOrderReceipt({
    required this.id,
    required this.total,
    this.itemCount = 0,
    this.paymentStatus,
  });

  factory DemoOrderReceipt.fromMap(Map<String, dynamic> map) {
    final totalValue = map['total_amount'] ?? map['total'];
    return DemoOrderReceipt(
      id: (map['order_id'] ?? map['id']).toString(),
      total: (totalValue as num).toDouble(),
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      paymentStatus: map['payment_status'] as String?,
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

  String get displayCode {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || normalizedId.toLowerCase() == 'null') {
      return 'UNKNOWN';
    }
    final prefix = normalizedId.length > 8
        ? normalizedId.substring(0, 8)
        : normalizedId;
    return prefix.toUpperCase();
  }

  factory DemoOrder.fromMap(Map<String, dynamic> map) {
    final rawItems = map['order_items'] as List<dynamic>? ?? const [];
    final totalValue = map['total_amount'] ?? map['total'];
    return DemoOrder(
      id: map['id']?.toString() ?? '',
      status: map['status'] as String? ?? 'pending',
      paymentStatus: map['payment_status'] as String? ?? 'unpaid',
      total: (totalValue as num).toDouble(),
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
    final lineTotal =
        map['line_total'] ??
        ((map['unit_price'] as num?) ?? 0) * ((map['quantity'] as num?) ?? 0);
    return DemoOrderItem(
      productName: map['product_name'] as String? ?? 'Product',
      unitPrice: (map['unit_price'] as num).toDouble(),
      quantity: (map['quantity'] as num).toInt(),
      lineTotal: (lineTotal as num).toDouble(),
    );
  }
}
