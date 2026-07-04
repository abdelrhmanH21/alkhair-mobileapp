class TruckRemnantModel {
  final int productId;
  final String productName;
  final String productUnit;
  final double quantity;

  const TruckRemnantModel({
    required this.productId,
    required this.productName,
    required this.productUnit,
    required this.quantity,
  });

  factory TruckRemnantModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    return TruckRemnantModel(
      productId: json['product_id'] as int? ?? product['id'] as int? ?? 0,
      productName: product['name'] as String? ?? '',
      productUnit: product['unit'] as String? ?? '',
      quantity: (json['current_stock_qty'] as num? ?? 0).toDouble(),
    );
  }
}

class DamagedGoodModel {
  final String productName;
  final double totalQuantity;
  final double totalValue;

  const DamagedGoodModel({
    required this.productName,
    required this.totalQuantity,
    required this.totalValue,
  });

  factory DamagedGoodModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    return DamagedGoodModel(
      productName: product['name'] as String? ?? '',
      totalQuantity: (json['total_quantity'] as num? ?? 0).toDouble(),
      totalValue: (json['total_value'] as num? ?? 0).toDouble(),
    );
  }
}

/// Mirrors AdminDelegateController::myShiftSummary (shared
/// BuildsDelegateShiftBreakdown trait on the alkhair-erp backend) — the
/// delegate's own view of the same good/damaged goods breakdown the admin
/// sees before confirming a settlement.
class SettlementSummaryModel {
  final int loadingId;
  final int totalInvoices;
  final double totalGross;
  final double totalReturns;
  final double totalNet;
  final double totalCash;
  final double totalDebtAdded;
  final List<TruckRemnantModel> truckRemnants;
  final List<DamagedGoodModel> damagedGoods;
  // Non-null when a settlement request is already pending for this loading —
  // lets the app restore the "awaiting confirmation" state on a fresh app
  // start/tab mount, not just while the app stayed open after submitting.
  final int? settlementRequestId;

  const SettlementSummaryModel({
    required this.loadingId,
    required this.totalInvoices,
    required this.totalGross,
    required this.totalReturns,
    required this.totalNet,
    required this.totalCash,
    required this.totalDebtAdded,
    required this.truckRemnants,
    required this.damagedGoods,
    this.settlementRequestId,
  });

  factory SettlementSummaryModel.fromJson(Map<String, dynamic> json) {
    final loading = json['loading'] as Map<String, dynamic>? ?? {};
    return SettlementSummaryModel(
      loadingId: loading['id'] as int? ?? 0,
      totalInvoices: json['total_invoices'] as int? ?? 0,
      totalGross: (json['total_gross'] as num? ?? 0).toDouble(),
      totalReturns: (json['total_returns'] as num? ?? 0).toDouble(),
      totalNet: (json['total_net'] as num? ?? 0).toDouble(),
      totalCash: (json['total_cash'] as num? ?? 0).toDouble(),
      totalDebtAdded: (json['total_debt_added'] as num? ?? 0).toDouble(),
      truckRemnants: (json['truck_remnants'] as List? ?? [])
          .map((e) => TruckRemnantModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      damagedGoods: (json['damaged_goods'] as List? ?? [])
          .map((e) => DamagedGoodModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      settlementRequestId: json['settlement_request_id'] as int?,
    );
  }
}
