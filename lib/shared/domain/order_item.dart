class OrderItem {
  final String productId;
  final String productName;
  final double orderedQuantity;
  final double? deliveredQuantity; // Null means not yet processed/delivered
  final double pricePerUnit;
  final String unit;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.orderedQuantity,
    this.deliveredQuantity,
    required this.pricePerUnit,
    required this.unit,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['product_id'],
      productName: json['products']?['name'] ?? 'Unknown Product',
      orderedQuantity: (json['ordered_qty'] as num?)?.toDouble() ?? 0.0,
      deliveredQuantity: (json['packed_qty'] as num?)?.toDouble(),
      pricePerUnit: (json['price_at_order'] as num?)?.toDouble() ?? 0.0,
      unit: json['products']?['unit'] ?? 'unit',
    );
  }
}
