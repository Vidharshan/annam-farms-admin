class Profile {
  final String id;
  final String? fullName;
  final String? phone;
  final String? area; // kept for legacy if any
  final String? addressLine1;
  final String? addressLine2;
  final String? landmark;
  final String? city;
  final String? pincode;
  final double defaultDeliveryCost;
  final int? routeNo;

  Profile({
    required this.id,
    this.fullName,
    this.phone,
    this.area,
    this.addressLine1,
    this.addressLine2,
    this.landmark,
    this.city,
    this.pincode,
    this.defaultDeliveryCost = 0.0,
    this.routeNo,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'],
      fullName: json['full_name'],
      phone: json['phone'],
      area: json['area'] ?? json['city'], // fallback
      addressLine1: json['address_line1'],
      addressLine2: json['address_line2'],
      landmark: json['landmark'],
      city: json['city'],
      pincode: json['pincode'],
      defaultDeliveryCost: (json['delivery_cost'] as num?)?.toDouble() ?? 0.0,
      routeNo: json['route_no'] as int?,
    );
  }
}
