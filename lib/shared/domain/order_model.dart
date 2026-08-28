import 'order_item.dart';
export 'order_item.dart';

class Order {
  final String id;
  final String userId;
  final DateTime createdAt;
  final String status; // 'pending', 'confirmed', 'delivered', 'cancelled'
  final String paymentStatus;
  final double totalAmount;
  final double deliveryCost;
  final String? customerName;
  final String? customerArea;
  final String? customerPhone;
  final String? customerLandmark;
  final bool isArchived;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.status,
    required this.paymentStatus,
    required this.totalAmount,
    required this.deliveryCost,
    this.customerName,
    this.customerArea,
    this.customerPhone,
    this.customerLandmark,
    this.isArchived = false,
    required this.items,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      userId: json['user_id'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      status: json['status'],
      totalAmount: (json['final_amount'] ?? json['total_estimated_amount'] as num).toDouble(),
      items: (json['order_items'] as List).map((i) => OrderItem.fromJson(i)).toList(),
      paymentStatus: json['payment_status'] ?? 'pending',
      deliveryCost: (json['delivery_cost'] as num?)?.toDouble() ?? 0.0,
      customerName: json['profiles']?['full_name'],
      customerArea: json['profiles']?['area'],
      customerPhone: json['profiles']?['phone'],
      customerLandmark: json['profiles']?['landmark'],
      isArchived: json['is_archived'] ?? false,
    );
  }
}
