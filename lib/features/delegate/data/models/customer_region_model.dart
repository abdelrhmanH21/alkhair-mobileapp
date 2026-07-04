class CustomerRegionModel {
  final int id;
  final String name;
  final bool isActive;

  const CustomerRegionModel({
    required this.id,
    required this.name,
    required this.isActive,
  });

  factory CustomerRegionModel.fromJson(Map<String, dynamic> json) {
    return CustomerRegionModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
