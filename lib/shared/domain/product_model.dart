class ProductModel {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String imageUrl;
  final String unit;
  final double price;
  final double currentStock;
  final bool isActive;
  final String orderType;
  final String? denomSet;

  ProductModel({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.unit,
    required this.price,
    required this.currentStock,
    required this.isActive,
    required this.orderType,
    this.denomSet,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? 'https://via.placeholder.com/150',
      unit: json['unit'] as String,
      price: (json['price'] as num).toDouble(),
      currentStock: (json['current_stock'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      orderType: json['order_type'] as String? ?? 'weight',
      denomSet: json['denom_set'] as String?,
    );
  }
}
