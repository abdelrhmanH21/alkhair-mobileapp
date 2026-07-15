/// Mirrors DelegateReportController::byRegion() rows.
class RegionReportRowModel {
  final int? regionId;
  final String regionName;
  final int customerCount;
  final double totalSales;
  final double participationPct;
  final double avgPerCustomer;

  const RegionReportRowModel({
    required this.regionId,
    required this.regionName,
    required this.customerCount,
    required this.totalSales,
    required this.participationPct,
    required this.avgPerCustomer,
  });

  factory RegionReportRowModel.fromJson(Map<String, dynamic> json) => RegionReportRowModel(
        regionId: json['region_id'] as int?,
        regionName: json['region_name'] as String? ?? '',
        customerCount: (json['customer_count'] as num? ?? 0).toInt(),
        totalSales: (json['total_sales'] as num? ?? 0).toDouble(),
        participationPct: (json['participation_pct'] as num? ?? 0).toDouble(),
        avgPerCustomer: (json['avg_per_customer'] as num? ?? 0).toDouble(),
      );
}

/// Mirrors DelegateReportController::byProduct() rows.
class ProductReportRowModel {
  final int productId;
  final String productName;
  final String unit;
  final double totalQuantitySold;
  final double totalValue;

  const ProductReportRowModel({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.totalQuantitySold,
    required this.totalValue,
  });

  factory ProductReportRowModel.fromJson(Map<String, dynamic> json) => ProductReportRowModel(
        productId: json['product_id'] as int,
        productName: json['product_name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        totalQuantitySold: (json['total_quantity_sold'] as num? ?? 0).toDouble(),
        totalValue: (json['total_value'] as num? ?? 0).toDouble(),
      );
}
