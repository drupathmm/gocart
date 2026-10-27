class MerchantSalesTrendPoint {
  const MerchantSalesTrendPoint({required this.date, required this.amount});

  final DateTime date;
  final double amount;

  factory MerchantSalesTrendPoint.fromMap(Map<String, dynamic> map) =>
      MerchantSalesTrendPoint(
        date: DateTime.parse(map['date'].toString()),
        amount: _number(map['amount']).toDouble(),
      );
}

class MerchantTopProduct {
  const MerchantTopProduct({
    required this.name,
    required this.quantity,
    required this.sales,
  });

  final String name;
  final int quantity;
  final double sales;

  factory MerchantTopProduct.fromMap(Map<String, dynamic> map) =>
      MerchantTopProduct(
        name: map['product_name']?.toString() ?? 'Product',
        quantity: _number(map['quantity']).toInt(),
        sales: _number(map['sales']).toDouble(),
      );
}

class MerchantRecentOrder {
  const MerchantRecentOrder({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.paidItemSales,
    required this.itemQuantity,
  });

  final String id;
  final String status;
  final DateTime createdAt;
  final double paidItemSales;
  final int itemQuantity;

  factory MerchantRecentOrder.fromMap(Map<String, dynamic> map) =>
      MerchantRecentOrder(
        id: map['order_id']?.toString() ?? '',
        status: map['status']?.toString() ?? 'unknown',
        createdAt: DateTime.parse(map['created_at'].toString()),
        paidItemSales: _number(map['paid_item_sales']).toDouble(),
        itemQuantity: _number(map['item_quantity']).toInt(),
      );
}

class MerchantAnalytics {
  const MerchantAnalytics({
    required this.currency,
    required this.paidItemSales,
    required this.totalOrders,
    required this.pendingOrders,
    required this.completedOrders,
    required this.salesTrend,
    required this.topProducts,
    required this.recentOrders,
  });

  final String currency;
  final double paidItemSales;
  final int totalOrders;
  final int pendingOrders;
  final int completedOrders;
  final List<MerchantSalesTrendPoint> salesTrend;
  final List<MerchantTopProduct> topProducts;
  final List<MerchantRecentOrder> recentOrders;

  bool get isEmpty => totalOrders == 0;

  factory MerchantAnalytics.fromResponse(dynamic response) {
    if (response is! Map) {
      throw const FormatException('Merchant analytics response is invalid.');
    }
    final map = Map<String, dynamic>.from(response);
    return MerchantAnalytics(
      currency: map['currency']?.toString() ?? 'INR',
      paidItemSales: _number(map['paid_item_sales']).toDouble(),
      totalOrders: _number(map['total_orders']).toInt(),
      pendingOrders: _number(map['pending_orders']).toInt(),
      completedOrders: _number(map['completed_orders']).toInt(),
      salesTrend: _maps(
        map['sales_trend'],
      ).map(MerchantSalesTrendPoint.fromMap).toList(),
      topProducts: _maps(
        map['top_products'],
      ).map(MerchantTopProduct.fromMap).toList(),
      recentOrders: _maps(
        map['recent_orders'],
      ).map(MerchantRecentOrder.fromMap).toList(),
    );
  }
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
