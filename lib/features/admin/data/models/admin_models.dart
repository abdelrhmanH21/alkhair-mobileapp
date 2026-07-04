/// Parses a field that may arrive as either a JSON number or a numeric
/// string (Laravel's `decimal:N` Eloquent cast always serializes as a
/// string, e.g. "55.00", unlike `float`/`double` casts).
double _asDouble(dynamic value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

class DashboardStatsModel {
  final int todayInvoicesCount;
  final double todayGrossSales;
  final double todayCashCollected;
  final double todayNewDebt;
  final int activeLoadings;
  final List<TopProductModel> topProducts;

  const DashboardStatsModel({
    required this.todayInvoicesCount,
    required this.todayGrossSales,
    required this.todayCashCollected,
    required this.todayNewDebt,
    required this.activeLoadings,
    required this.topProducts,
  });

  factory DashboardStatsModel.fromJson(Map<String, dynamic> json) =>
      DashboardStatsModel(
        todayInvoicesCount: json['today_invoices_count'] as int? ?? 0,
        todayGrossSales:
            (json['today_gross_sales'] as num? ?? 0).toDouble(),
        todayCashCollected:
            (json['today_cash_collected'] as num? ?? 0).toDouble(),
        todayNewDebt: (json['today_new_debt'] as num? ?? 0).toDouble(),
        activeLoadings: json['active_loadings'] as int? ?? 0,
        topProducts: (json['top_products_today'] as List? ?? [])
            .map((e) => TopProductModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TopProductModel {
  final String name;
  final double totalQty;
  final double totalRevenue;
  const TopProductModel(
      {required this.name, required this.totalQty, required this.totalRevenue});
  factory TopProductModel.fromJson(Map<String, dynamic> json) =>
      TopProductModel(
        name: json['name'] as String,
        totalQty: (json['total_qty'] as num).toDouble(),
        totalRevenue: (json['total_revenue'] as num).toDouble(),
      );
}

class DelegateModel {
  final int id;
  final String name;
  final String email;
  final bool isActive;
  final bool hasActiveShift;

  const DelegateModel({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.hasActiveShift,
  });

  factory DelegateModel.fromJson(Map<String, dynamic> json) => DelegateModel(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        hasActiveShift: json['has_active_shift'] as bool? ?? false,
      );
}

class SimpleProductModel {
  final int id;
  final String name;
  final String unit;
  final double salePrice;

  const SimpleProductModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.salePrice,
  });

  factory SimpleProductModel.fromJson(Map<String, dynamic> json) =>
      SimpleProductModel(
        id: json['id'] as int,
        name: json['name'] as String,
        unit: json['unit'] as String? ?? '',
        // Product.sale_price is an Eloquent `decimal:2` cast, which Laravel
        // always serializes as a JSON string (e.g. "55.00"), not a number.
        salePrice: _asDouble(json['sale_price']),
      );

  @override
  String toString() => name;
}

class SimpleWarehouseModel {
  final int id;
  final String name;
  final String type;

  const SimpleWarehouseModel({
    required this.id,
    required this.name,
    required this.type,
  });

  factory SimpleWarehouseModel.fromJson(Map<String, dynamic> json) =>
      SimpleWarehouseModel(
        id: json['id'] as int,
        name: json['name'] as String,
        type: json['type'] as String? ?? '',
      );

  @override
  String toString() => name;
}

class ShiftSummaryModel {
  final Map<String, dynamic> delegate;
  final int totalInvoices;
  final double totalGross;
  final double totalReturns;
  final double totalNet;
  final double totalCash;
  final double totalDebtAdded;
  final List<Map<String, dynamic>> truckRemnants;
  final List<Map<String, dynamic>> damagedGoods;

  const ShiftSummaryModel({
    required this.delegate,
    required this.totalInvoices,
    required this.totalGross,
    required this.totalReturns,
    required this.totalNet,
    required this.totalCash,
    required this.totalDebtAdded,
    required this.truckRemnants,
    required this.damagedGoods,
  });

  factory ShiftSummaryModel.fromJson(Map<String, dynamic> json) =>
      ShiftSummaryModel(
        delegate: json['delegate'] as Map<String, dynamic>? ?? {},
        totalInvoices: json['total_invoices'] as int? ?? 0,
        totalGross: (json['total_gross'] as num? ?? 0).toDouble(),
        totalReturns: (json['total_returns'] as num? ?? 0).toDouble(),
        totalNet: (json['total_net'] as num? ?? 0).toDouble(),
        totalCash: (json['total_cash'] as num? ?? 0).toDouble(),
        totalDebtAdded: (json['total_debt_added'] as num? ?? 0).toDouble(),
        truckRemnants: List<Map<String, dynamic>>.from(
            json['truck_remnants'] as List? ?? []),
        damagedGoods: List<Map<String, dynamic>>.from(
            json['damaged_goods'] as List? ?? []),
      );
}
