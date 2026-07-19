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
  final double workingCapital;
  final WorkingCapitalBreakdownModel workingCapitalBreakdown;

  const DashboardStatsModel({
    required this.todayInvoicesCount,
    required this.todayGrossSales,
    required this.todayCashCollected,
    required this.todayNewDebt,
    required this.activeLoadings,
    required this.topProducts,
    required this.workingCapital,
    required this.workingCapitalBreakdown,
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
        workingCapital: _asDouble(json['working_capital']),
        workingCapitalBreakdown: WorkingCapitalBreakdownModel.fromJson(
            json['working_capital_breakdown'] as Map<String, dynamic>? ?? {}),
      );
}

class WorkingCapitalBreakdownModel {
  final double cash;
  final double rawMaterials;
  final double finishedGoods;
  final double inventoryValue;
  final double receivables;
  final double payables;

  const WorkingCapitalBreakdownModel({
    required this.cash,
    required this.rawMaterials,
    required this.finishedGoods,
    required this.inventoryValue,
    required this.receivables,
    required this.payables,
  });

  factory WorkingCapitalBreakdownModel.fromJson(Map<String, dynamic> json) =>
      WorkingCapitalBreakdownModel(
        cash: _asDouble(json['cash']),
        rawMaterials: _asDouble(json['raw_materials']),
        finishedGoods: _asDouble(json['finished_goods']),
        inventoryValue: _asDouble(json['inventory_value']),
        receivables: _asDouble(json['receivables']),
        payables: _asDouble(json['payables']),
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
        // total_qty/total_revenue come from a raw SUM() over decimal
        // columns (dashboardStats()'s selectRaw query) — MySQL/PDO returns
        // decimal aggregates as strings, bypassing Eloquent casts entirely.
        totalQty: _asDouble(json['total_qty']),
        totalRevenue: _asDouble(json['total_revenue']),
      );
}

/// Mirrors delegate_loadings.status, plus an idle state for delegates with no
/// unsettled loading at all — drives the "متابعة المناديب" status badge.
enum DelegateTrackingStatus {
  idle,
  pendingPickup,
  accepted,
  inTransit,
  completed,
  awaitingSettlementConfirmation,
}

class DelegateModel {
  final int id;
  final String name;
  final String email;
  final bool isActive;
  final bool hasActiveShift;
  final String? loadingStatus;
  final bool hasPendingSettlementRequest;

  const DelegateModel({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    required this.hasActiveShift,
    this.loadingStatus,
    this.hasPendingSettlementRequest = false,
  });

  factory DelegateModel.fromJson(Map<String, dynamic> json) => DelegateModel(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String? ?? '',
        isActive: json['is_active'] as bool? ?? true,
        hasActiveShift: json['has_active_shift'] as bool? ?? false,
        loadingStatus: json['loading_status'] as String?,
        hasPendingSettlementRequest:
            json['has_pending_settlement_request'] as bool? ?? false,
      );

  /// A pending settlement request takes priority over the raw loading status
  /// — it's the state that actually needs admin action next.
  DelegateTrackingStatus get trackingStatus {
    if (hasPendingSettlementRequest) {
      return DelegateTrackingStatus.awaitingSettlementConfirmation;
    }
    switch (loadingStatus) {
      case 'pending_pickup':
        return DelegateTrackingStatus.pendingPickup;
      case 'accepted':
        return DelegateTrackingStatus.accepted;
      case 'in_transit':
        return DelegateTrackingStatus.inTransit;
      case 'completed':
        return DelegateTrackingStatus.completed;
      default:
        return DelegateTrackingStatus.idle;
    }
  }

  /// buildShiftBreakdown() (backing the shift-summary/settle screen) only
  /// ever matches accepted/in_transit/completed loadings — pending_pickup
  /// has no breakdown to show yet, so it's excluded here.
  bool get canOpenShiftDetail =>
      loadingStatus == 'accepted' ||
      loadingStatus == 'in_transit' ||
      loadingStatus == 'completed';
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
  // Settlement now requires a pending request the delegate submitted from
  // the app — null means there's nothing to settle against yet.
  final int? settlementRequestId;
  final double? declaredCashAmount;
  final double? declaredWalletAmount;

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
    this.settlementRequestId,
    this.declaredCashAmount,
    this.declaredWalletAmount,
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
        settlementRequestId: json['settlement_request_id'] as int?,
        // declared_cash_amount/declared_wallet_amount come from
        // DelegateSettlementRequest's decimal:2-cast columns, which Laravel
        // always serializes as strings.
        declaredCashAmount: json['declared_cash_amount'] == null
            ? null
            : _asDouble(json['declared_cash_amount']),
        declaredWalletAmount: json['declared_wallet_amount'] == null
            ? null
            : _asDouble(json['declared_wallet_amount']),
      );
}
