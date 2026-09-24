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

/// Mirrors CompanyReportController::treasuries() rows (تقرير الخزائن,
/// admin/manager only). balance is CURRENT; the rest is period-scoped.
class TreasuryReportRowModel {
  final int treasuryId;
  final String treasuryName;
  final double balance;
  final double totalCredit;
  final double totalDebit;
  final double netMovement;
  final int transactionCount;

  const TreasuryReportRowModel({
    required this.treasuryId,
    required this.treasuryName,
    required this.balance,
    required this.totalCredit,
    required this.totalDebit,
    required this.netMovement,
    required this.transactionCount,
  });

  factory TreasuryReportRowModel.fromJson(Map<String, dynamic> json) => TreasuryReportRowModel(
        treasuryId: json['treasury_id'] as int,
        treasuryName: json['treasury_name'] as String? ?? '',
        balance: (json['balance'] as num? ?? 0).toDouble(),
        totalCredit: (json['total_credit'] as num? ?? 0).toDouble(),
        totalDebit: (json['total_debit'] as num? ?? 0).toDouble(),
        netMovement: (json['net_movement'] as num? ?? 0).toDouble(),
        transactionCount: (json['transaction_count'] as num? ?? 0).toInt(),
      );
}

/// Mirrors CompanyReportController::suppliers() rows (تقرير الموردين,
/// admin/manager only). balance is CURRENT; purchases are period-scoped.
class SupplierReportRowModel {
  final int supplierId;
  final String supplierName;
  final double balance;
  final double totalPurchases;
  final double totalPaid;
  final int purchaseCount;

  const SupplierReportRowModel({
    required this.supplierId,
    required this.supplierName,
    required this.balance,
    required this.totalPurchases,
    required this.totalPaid,
    required this.purchaseCount,
  });

  factory SupplierReportRowModel.fromJson(Map<String, dynamic> json) => SupplierReportRowModel(
        supplierId: json['supplier_id'] as int,
        supplierName: json['supplier_name'] as String? ?? '',
        balance: (json['balance'] as num? ?? 0).toDouble(),
        totalPurchases: (json['total_purchases'] as num? ?? 0).toDouble(),
        totalPaid: (json['total_paid'] as num? ?? 0).toDouble(),
        purchaseCount: (json['purchase_count'] as num? ?? 0).toInt(),
      );
}
