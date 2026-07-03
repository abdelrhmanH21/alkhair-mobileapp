class CatalogProductModel {
  final int id;
  final String name;
  final String unit;
  final double salePrice;

  const CatalogProductModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.salePrice,
  });

  factory CatalogProductModel.fromJson(Map<String, dynamic> json) {
    return CatalogProductModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      salePrice: (json['sale_price'] as num? ?? 0).toDouble(),
    );
  }
}
