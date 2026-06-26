class CategoryModel {
  final String id;
  final String name;
  final String imageUrl;
  final int sortOrder;

  CategoryModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.sortOrder,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String? ?? 'https://via.placeholder.com/150', // Fallback
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
