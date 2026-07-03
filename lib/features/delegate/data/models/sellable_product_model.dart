class SellableProductModel {
  final int productId;
  final String name;
  final String unit;
  final double availableQty;
  final double unitPrice;

  const SellableProductModel({
    required this.productId,
    required this.name,
    required this.unit,
    required this.availableQty,
    required this.unitPrice,
  });

  factory SellableProductModel.fromJson(Map<String, dynamic> json) {
    return SellableProductModel(
      productId: json['product_id'] as int,
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      availableQty: (json['available_qty'] as num? ?? 0).toDouble(),
      unitPrice: (json['unit_price'] as num? ?? 0).toDouble(),
    );
  }
}
