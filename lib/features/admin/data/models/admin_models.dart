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

// ─── Expenses & Treasuries (المصروفات والخزائن) ────────────────────────────
// Mirrors ExpenseController/TreasuryController — the same endpoints the web
// ERP uses (GET /expenses, /treasuries, /expense-items, POST /expenses),
// reached here via ApiEndpoints.apiRoot since no mobile-specific admin
// endpoint was needed for this data.

class ExpenseCategoryModel {
  final int id;
  final String name;
  const ExpenseCategoryModel({required this.id, required this.name});

  factory ExpenseCategoryModel.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
      );

  @override
  String toString() => name;
}

class TreasuryModel {
  final int id;
  final String name;
  final double balance;
  final String currency;
  final bool isDefault;

  const TreasuryModel({
    required this.id,
    required this.name,
    required this.balance,
    required this.currency,
    required this.isDefault,
  });

  factory TreasuryModel.fromJson(Map<String, dynamic> json) => TreasuryModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        balance: _asDouble(json['balance']),
        currency: json['currency'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
      );

  @override
  String toString() => name;
}

class ExpenseModel {
  final int id;
  final String? categoryName;
  final String treasuryName;
  final String description;
  final double amount;
  final DateTime expenseDate;
  final String? notes;
  final String createdByName;
  // A non-null delegate_loading_id means this expense was recorded by a
  // delegate mid-route (DelegateExpenseController::store) rather than an
  // accountant from the web/mobile "المصروفات" screen — same مصدر concept
  // SaleController::combined() uses for sales, just a single unified table
  // here instead of a UNION since Expense already carries the nullable FK.
  final bool isDelegateSourced;

  const ExpenseModel({
    required this.id,
    required this.categoryName,
    required this.treasuryName,
    required this.description,
    required this.amount,
    required this.expenseDate,
    required this.notes,
    required this.createdByName,
    required this.isDelegateSourced,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    final treasury = json['treasury'] as Map<String, dynamic>?;
    final createdBy = json['created_by'] as Map<String, dynamic>?;
    return ExpenseModel(
      id: json['id'] as int,
      categoryName: category?['name'] as String?,
      treasuryName: treasury?['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      amount: _asDouble(json['amount']),
      expenseDate:
          DateTime.tryParse(json['expense_date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
      createdByName: createdBy?['name'] as String? ?? '',
      isDelegateSourced: json['delegate_loading_id'] != null,
    );
  }
}

class ExpensePageModel {
  final List<ExpenseModel> data;
  final int currentPage;
  final int lastPage;
  const ExpensePageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory ExpensePageModel.fromJson(Map<String, dynamic> json) => ExpensePageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

// ─── Customers & Suppliers (بيانات العملاء والموردين) ──────────────────────
// Mirrors CustomerController/SupplierController — same GET /customers,
// /suppliers the web ERP uses.

class CustomerModel {
  final int id;
  final String name;
  final String? phone;
  final double balance;
  final String? regionName;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.regionName,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    final region = json['region'] as Map<String, dynamic>?;
    return CustomerModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      balance: _asDouble(json['balance']),
      regionName: region?['name'] as String?,
    );
  }
}

class CustomerPageModel {
  final List<CustomerModel> data;
  final int currentPage;
  final int lastPage;
  const CustomerPageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory CustomerPageModel.fromJson(Map<String, dynamic> json) => CustomerPageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => CustomerModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

class SupplierModel {
  final int id;
  final String name;
  final String? phone;
  final double balance;

  const SupplierModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json) => SupplierModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        balance: _asDouble(json['balance']),
      );
}

class SupplierPageModel {
  final List<SupplierModel> data;
  final int currentPage;
  final int lastPage;
  const SupplierPageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory SupplierPageModel.fromJson(Map<String, dynamic> json) => SupplierPageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => SupplierModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

// ─── Sales & collections (المبيعات والتحصيلات) ─────────────────────────────
// Mirrors SaleController::combined() (GET /sales/combined) — the same
// read-only UNION of `sales` (web) + `delegate_invoices` (delegate app)
// rows the web "المبيعات" screen already lists, and
// PaymentCollectionController::index() (GET /payment-collections).

class SalesCombinedRowModel {
  final int id;
  final String source; // 'web' | 'delegate'
  final String invoiceNumber;
  final int? customerId;
  final String customerName;
  final String? repName;
  final DateTime date;
  final double total;
  final double paidAmount;
  final String paymentStatus;

  const SalesCombinedRowModel({
    required this.id,
    required this.source,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.repName,
    required this.date,
    required this.total,
    required this.paidAmount,
    required this.paymentStatus,
  });

  bool get isDelegateSourced => source == 'delegate';

  factory SalesCombinedRowModel.fromJson(Map<String, dynamic> json) =>
      SalesCombinedRowModel(
        id: json['id'] as int,
        source: json['source'] as String? ?? 'web',
        invoiceNumber: json['invoice_number'] as String? ?? '',
        customerId: json['customer_id'] as int?,
        customerName: json['customer_name'] as String? ?? '',
        repName: json['rep_name'] as String?,
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        total: _asDouble(json['total']),
        paidAmount: _asDouble(json['paid_amount']),
        paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      );
}

class SalesCombinedPageModel {
  final List<SalesCombinedRowModel> data;
  final int currentPage;
  final int lastPage;
  const SalesCombinedPageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory SalesCombinedPageModel.fromJson(Map<String, dynamic> json) =>
      SalesCombinedPageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => SalesCombinedRowModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

class CollectionModel {
  final int id;
  final String customerName;
  final String treasuryName;
  final double amount;
  final DateTime date;
  final String? notes;

  const CollectionModel({
    required this.id,
    required this.customerName,
    required this.treasuryName,
    required this.amount,
    required this.date,
    this.notes,
  });

  factory CollectionModel.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>?;
    final treasury = json['treasury'] as Map<String, dynamic>?;
    return CollectionModel(
      id: json['id'] as int,
      customerName: customer?['name'] as String? ?? 'غير معروف',
      treasuryName: treasury?['name'] as String? ?? '',
      amount: _asDouble(json['amount']),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
    );
  }
}

class CollectionPageModel {
  final List<CollectionModel> data;
  final int currentPage;
  final int lastPage;
  const CollectionPageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory CollectionPageModel.fromJson(Map<String, dynamic> json) => CollectionPageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => CollectionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

// ─── Payroll (العمالة) ──────────────────────────────────────────────────────
// Mirrors AdminDelegateController::payrollSummary() — one row per active
// sales rep, same SalesRepPayrollService calculations the delegate's own
// dashboard() already surfaces for a single rep.

class PayrollSummaryRowModel {
  final int repId;
  final String repName;
  final String? phone;
  final double monthlyTarget;
  final double achievedThisMonth;
  final double? targetPercentage;
  final double commissionEarned;
  final double penaltiesTotal;
  final double advancesTotal;
  final double netPayable;

  const PayrollSummaryRowModel({
    required this.repId,
    required this.repName,
    required this.phone,
    required this.monthlyTarget,
    required this.achievedThisMonth,
    required this.targetPercentage,
    required this.commissionEarned,
    required this.penaltiesTotal,
    required this.advancesTotal,
    required this.netPayable,
  });

  factory PayrollSummaryRowModel.fromJson(Map<String, dynamic> json) =>
      PayrollSummaryRowModel(
        repId: json['rep_id'] as int,
        repName: json['rep_name'] as String? ?? '',
        phone: json['phone'] as String?,
        monthlyTarget: _asDouble(json['monthly_target']),
        achievedThisMonth: _asDouble(json['achieved_this_month']),
        targetPercentage: json['target_percentage'] == null
            ? null
            : _asDouble(json['target_percentage']),
        commissionEarned: _asDouble(json['commission_earned']),
        penaltiesTotal: _asDouble(json['penalties_total']),
        advancesTotal: _asDouble(json['advances_total']),
        netPayable: _asDouble(json['net_payable']),
      );
}
