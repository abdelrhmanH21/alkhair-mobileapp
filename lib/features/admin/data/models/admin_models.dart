import '../../../../core/utils/date_parsing.dart';

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
  final MonthComparisonModel monthComparison;

  const DashboardStatsModel({
    required this.todayInvoicesCount,
    required this.todayGrossSales,
    required this.todayCashCollected,
    required this.todayNewDebt,
    required this.activeLoadings,
    required this.topProducts,
    required this.workingCapital,
    required this.workingCapitalBreakdown,
    required this.monthComparison,
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
        monthComparison: MonthComparisonModel.fromJson(
            json['month_comparison'] as Map<String, dynamic>? ?? {}),
      );
}

/// One MoM metric — current vs previous calendar month + % change (null
/// when the previous month was zero, to avoid a divide-by-zero on the
/// backend). Mirrors MonthComparisonCalculator's response shape exactly,
/// shared by both DashboardController (web) and this mobile endpoint.
class MonthComparisonMetricModel {
  final double currentMonthValue;
  final double previousMonthValue;
  final double? percentageChange;

  const MonthComparisonMetricModel({
    required this.currentMonthValue,
    required this.previousMonthValue,
    required this.percentageChange,
  });

  factory MonthComparisonMetricModel.fromJson(Map<String, dynamic> json) =>
      MonthComparisonMetricModel(
        currentMonthValue: _asDouble(json['current_month_value']),
        previousMonthValue: _asDouble(json['previous_month_value']),
        percentageChange: json['percentage_change'] == null
            ? null
            : (json['percentage_change'] as num).toDouble(),
      );

  static const _zero = MonthComparisonMetricModel(
      currentMonthValue: 0, previousMonthValue: 0, percentageChange: null);
}

class MonthComparisonModel {
  final MonthComparisonMetricModel totalSales;
  final MonthComparisonMetricModel totalExpenses;
  final MonthComparisonMetricModel profitMargin;

  const MonthComparisonModel({
    required this.totalSales,
    required this.totalExpenses,
    required this.profitMargin,
  });

  factory MonthComparisonModel.fromJson(Map<String, dynamic> json) =>
      MonthComparisonModel(
        totalSales: json['total_sales'] == null
            ? MonthComparisonMetricModel._zero
            : MonthComparisonMetricModel.fromJson(
                json['total_sales'] as Map<String, dynamic>),
        totalExpenses: json['total_expenses'] == null
            ? MonthComparisonMetricModel._zero
            : MonthComparisonMetricModel.fromJson(
                json['total_expenses'] as Map<String, dynamic>),
        profitMargin: json['profit_margin'] == null
            ? MonthComparisonMetricModel._zero
            : MonthComparisonMetricModel.fromJson(
                json['profit_margin'] as Map<String, dynamic>),
      );
}

class WorkingCapitalBreakdownModel {
  final double cash;
  final double rawMaterials;
  final double finishedGoods;
  final double inventoryValue;
  final double receivables;
  final double payrollPaidToDate;
  final double payables;

  const WorkingCapitalBreakdownModel({
    required this.cash,
    required this.rawMaterials,
    required this.finishedGoods,
    required this.inventoryValue,
    required this.receivables,
    required this.payrollPaidToDate,
    required this.payables,
  });

  factory WorkingCapitalBreakdownModel.fromJson(Map<String, dynamic> json) =>
      WorkingCapitalBreakdownModel(
        cash: _asDouble(json['cash']),
        rawMaterials: _asDouble(json['raw_materials']),
        finishedGoods: _asDouble(json['finished_goods']),
        inventoryValue: _asDouble(json['inventory_value']),
        receivables: _asDouble(json['receivables']),
        payrollPaidToDate: _asDouble(json['payroll_paid_to_date']),
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
  // Proof-of-expense photo — only ever set for delegate-submitted expenses
  // (DelegateExpenseController::store() requires it); admin-recorded
  // expenses from this same list have no photo, same as before.
  final String? photoUrl;

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
    required this.photoUrl,
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
      expenseDate: parseServerDateTime(json['expense_date'] as String?),
      notes: json['notes'] as String?,
      createdByName: createdBy?['name'] as String? ?? '',
      isDelegateSourced: json['delegate_loading_id'] != null,
      photoUrl: json['photo_url'] as String?,
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
  // "مورد×عميل" — the linked Customer id/name, if this supplier has been
  // marked as also being a customer (Supplier::linkedCustomer()).
  final int? linkedCustomerId;
  final String? linkedCustomerName;

  const SupplierModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    this.linkedCustomerId,
    this.linkedCustomerName,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json) {
    final linkedCustomer = json['linked_customer'] as Map<String, dynamic>?;
    return SupplierModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String?,
      balance: _asDouble(json['balance']),
      linkedCustomerId: json['linked_customer_id'] as int?,
      linkedCustomerName: linkedCustomer?['name'] as String?,
    );
  }
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
        date: parseServerDateTime(json['date'] as String?),
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
      date: parseServerDateTime(json['date'] as String?),
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
  final double bonusTotal;
  final double netPayable;
  // Whether users.sales_rep_id points at this rep — drives the "حذف نهائي"
  // action on the rep detail page. See SalesRepController::forceDestroy().
  final bool hasLinkedUser;

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
    required this.bonusTotal,
    required this.netPayable,
    required this.hasLinkedUser,
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
        bonusTotal: _asDouble(json['bonus_total']),
        netPayable: _asDouble(json['net_payable']),
        hasLinkedUser: json['has_linked_user'] as bool? ?? false,
      );
}

/// Mirrors SalesRepController::index() rows — used by the "عمليات العمالة"
/// worker picker, which (unlike PayrollSummaryRowModel's sales_rep-only
/// list) must include worker_type=worker rows too, per the original
/// "العمالة" web page's staff list covering both.
class StaffModel {
  final int id;
  final String name;
  final String workerType;
  final String? phone;

  const StaffModel({
    required this.id,
    required this.name,
    required this.workerType,
    this.phone,
  });

  factory StaffModel.fromJson(Map<String, dynamic> json) => StaffModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        workerType: json['worker_type'] as String? ?? 'sales_rep',
        phone: json['phone'] as String?,
      );
}

// ─── Simple id+name reference data (التصنيفات/المعامل) ─────────────────────

class IdNameModel {
  final int id;
  final String name;
  const IdNameModel({required this.id, required this.name});

  factory IdNameModel.fromJson(Map<String, dynamic> json) => IdNameModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
      );

  @override
  String toString() => name;
}

// ─── Raw materials (تعديل سعر) ──────────────────────────────────────────────

class RawMaterialModel {
  final int id;
  final String name;
  final String unit;
  final double costPrice;
  final double currentStock;

  const RawMaterialModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.costPrice,
    required this.currentStock,
  });

  factory RawMaterialModel.fromJson(Map<String, dynamic> json) => RawMaterialModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        costPrice: _asDouble(json['cost_price']),
        currentStock: _asDouble(json['current_stock']),
      );

  @override
  String toString() => name;
}

// ─── Manufacturing recipes ("بدء تشغيلة جديدة") ─────────────────────────────
// Mirrors ManufacturingRecipeController::index()/show() — same recipe
// records the web MaterialIssuancePage.tsx uses to build the input/output
// form for "بدء تشغيلة معمل".

class RecipeInputModel {
  final int id;
  final String inputType; // 'raw_material' | 'product'
  final int? rawMaterialId;
  final int? productId;
  final double defaultQuantity;
  final String name;
  final String unit;
  final double? currentStock; // raw materials only

  const RecipeInputModel({
    required this.id,
    required this.inputType,
    required this.rawMaterialId,
    required this.productId,
    required this.defaultQuantity,
    required this.name,
    required this.unit,
    required this.currentStock,
  });

  factory RecipeInputModel.fromJson(Map<String, dynamic> json) {
    final isProduct = json['input_type'] == 'product';
    final rawMaterial = json['raw_material'] as Map<String, dynamic>?;
    final product = json['product'] as Map<String, dynamic>?;
    return RecipeInputModel(
      id: json['id'] as int,
      inputType: json['input_type'] as String? ?? 'raw_material',
      rawMaterialId: json['raw_material_id'] as int?,
      productId: json['product_id'] as int?,
      defaultQuantity: _asDouble(json['default_quantity']),
      name: isProduct
          ? (product?['name'] as String? ?? '')
          : (rawMaterial?['name'] as String? ?? ''),
      unit: (json['unit'] as String?) ??
          (isProduct ? (product?['unit'] as String? ?? '') : (rawMaterial?['unit'] as String? ?? '')),
      currentStock: isProduct ? null : _asDouble(rawMaterial?['current_stock']),
    );
  }
}

class RecipeOutputModel {
  final int id;
  final int productId;
  final bool isByproduct;
  final String name;
  final String unit;

  const RecipeOutputModel({
    required this.id,
    required this.productId,
    required this.isByproduct,
    required this.name,
    required this.unit,
  });

  factory RecipeOutputModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    return RecipeOutputModel(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      isByproduct: json['is_byproduct'] as bool? ?? false,
      name: product?['name'] as String? ?? '',
      unit: (json['unit'] as String?) ?? (product?['unit'] as String? ?? ''),
    );
  }
}

class RecipeModel {
  final int id;
  final String name;
  final int categoryId;
  final List<RecipeInputModel> inputs;
  final List<RecipeOutputModel> outputs;
  final int? outputWarehouseId;
  final bool allowProductReentry;

  const RecipeModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.inputs,
    required this.outputs,
    required this.outputWarehouseId,
    required this.allowProductReentry,
  });

  factory RecipeModel.fromJson(Map<String, dynamic> json) => RecipeModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        categoryId: json['category_id'] as int? ?? 0,
        inputs: (json['inputs'] as List? ?? [])
            .map((e) => RecipeInputModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputs: (json['outputs'] as List? ?? [])
            .map((e) => RecipeOutputModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputWarehouseId: json['output_warehouse_id'] as int?,
        allowProductReentry: json['allow_product_reentry'] as bool? ?? false,
      );
}

// ─── Production batches ("بدء تشغيلة جديدة"/"استلام إنتاج تام") ────────────
// Mirrors ManufacturingController::index()/show()/store()/complete() — same
// batch records the web ProductionBatchesPage/MaterialIssuancePage/
// ProductionReceivingPage use.

class ProductionBatchSummaryModel {
  final int id;
  final String? batchNumber;
  final String? recipeName;
  final String? categoryName;
  final String status;
  final DateTime createdAt;

  const ProductionBatchSummaryModel({
    required this.id,
    required this.batchNumber,
    required this.recipeName,
    required this.categoryName,
    required this.status,
    required this.createdAt,
  });

  factory ProductionBatchSummaryModel.fromJson(Map<String, dynamic> json) {
    final recipe = json['recipe'] as Map<String, dynamic>?;
    final category = recipe?['category'] as Map<String, dynamic>?;
    return ProductionBatchSummaryModel(
      id: json['id'] as int,
      batchNumber: json['batch_number'] as String?,
      recipeName: recipe?['name'] as String?,
      categoryName: category?['name'] as String?,
      status: json['status'] as String? ?? '',
      createdAt: parseServerDateTime(json['created_at'] as String?),
    );
  }
}

class ProductionMaterialModel {
  final int id;
  final String? materialName;
  final String? unit;
  final double quantityUsed;
  final double? actualQuantityUsed;
  final String itemType;
  final bool isReentry;

  const ProductionMaterialModel({
    required this.id,
    required this.materialName,
    required this.unit,
    required this.quantityUsed,
    required this.actualQuantityUsed,
    required this.itemType,
    required this.isReentry,
  });

  factory ProductionMaterialModel.fromJson(Map<String, dynamic> json) {
    final rawMaterial = json['raw_material'] as Map<String, dynamic>?;
    return ProductionMaterialModel(
      id: json['id'] as int,
      materialName: json['material_name'] as String? ?? rawMaterial?['name'] as String?,
      unit: json['unit'] as String?,
      quantityUsed: _asDouble(json['quantity_used']),
      actualQuantityUsed: json['actual_quantity_used'] == null
          ? null
          : _asDouble(json['actual_quantity_used']),
      itemType: json['item_type'] as String? ?? 'raw_material',
      isReentry: json['is_reentry'] as bool? ?? false,
    );
  }
}

class ProductionOutputModel {
  final int id;
  final int productId;
  final String productName;
  final String unit;
  final int? warehouseId;
  final bool isByproduct;
  final double? actualQuantity;

  const ProductionOutputModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unit,
    required this.warehouseId,
    required this.isByproduct,
    required this.actualQuantity,
  });

  factory ProductionOutputModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final warehouse = json['warehouse'] as Map<String, dynamic>?;
    return ProductionOutputModel(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      productName: product?['name'] as String? ?? '',
      unit: product?['unit'] as String? ?? '',
      warehouseId: json['warehouse_id'] as int? ?? warehouse?['id'] as int?,
      isByproduct: json['is_byproduct'] as bool? ?? false,
      actualQuantity:
          json['actual_quantity'] == null ? null : _asDouble(json['actual_quantity']),
    );
  }
}

class ProductionBatchDetailModel {
  final int id;
  final String? batchNumber;
  final String status;
  final String? notes;
  final List<ProductionMaterialModel> materials;
  final List<ProductionOutputModel> outputs;

  const ProductionBatchDetailModel({
    required this.id,
    required this.batchNumber,
    required this.status,
    required this.notes,
    required this.materials,
    required this.outputs,
  });

  factory ProductionBatchDetailModel.fromJson(Map<String, dynamic> json) =>
      ProductionBatchDetailModel(
        id: json['id'] as int,
        batchNumber: json['batch_number'] as String?,
        status: json['status'] as String? ?? '',
        notes: json['notes'] as String?,
        materials: (json['manufacturing_materials'] as List? ?? [])
            .map((e) => ProductionMaterialModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        outputs: (json['order_outputs'] as List? ?? [])
            .map((e) => ProductionOutputModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Admin sale ("عملية بيع") ────────────────────────────────────────────────

/// One `sale_items` row from the admin-sale response, product name/unit
/// read from its loaded `product` relation — same shape a receipt's items
/// table needs, just under Sale/SaleItem's own field names rather than
/// DelegateInvoiceItem's.
class AdminSaleItemModel {
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double subtotal;

  const AdminSaleItemModel({
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory AdminSaleItemModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>? ?? {};
    return AdminSaleItemModel(
      productName: product['name'] as String? ?? '',
      unit: product['unit'] as String? ?? '',
      quantity: _asDouble(json['quantity']),
      unitPrice: _asDouble(json['unit_price']),
      subtotal: _asDouble(json['total']),
    );
  }
}

/// AdminSaleController::store()'s response — a plain `Sale` (not a
/// DelegateInvoice) loaded with `customer`/`createdBy`/`items.product`.
/// Carries everything a receipt needs (see admin_sale_page.dart's
/// buildAdminSaleReceiptData adapter) rather than just the id/total/paid
/// summary this originally held, since the admin-sale screen shows a full
/// receipt preview/print right after submitting.
class AdminSaleResultModel {
  final int id;
  final String? invoiceNumber;
  final double totalAmount;
  final double paidAmount;
  final DateTime createdAt;
  final String customerName;
  final String customerPhone;
  // Customer.balance AFTER this sale's own remaining-debt increment was
  // applied (AdminSaleController::store() increments it within the same
  // request/transaction) — the receipt adapter derives the customer's
  // PRIOR debt from this by subtracting this sale's own remaining amount,
  // mirroring DelegateInvoiceController's prior_debt snapshot semantics.
  final double customerBalanceAfterSale;
  // `created_by` in the raw JSON is the loaded User relation object (Sale's
  // own `created_by` FK column and the `createdBy()` relation share the
  // same snake_case key, so the eager-loaded relation wins in the
  // serialized response) — this is the admin/manager who recorded the
  // sale, shown as "المندوب:" on the receipt since there's no delegate.
  final String createdByName;
  final List<AdminSaleItemModel> items;

  const AdminSaleResultModel({
    required this.id,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.paidAmount,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.customerBalanceAfterSale,
    required this.createdByName,
    required this.items,
  });

  factory AdminSaleResultModel.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? {};
    final createdBy = json['created_by'] as Map<String, dynamic>? ?? {};
    final items = json['items'] as List? ?? [];
    return AdminSaleResultModel(
      id: json['id'] as int,
      invoiceNumber: json['invoice_number'] as String?,
      totalAmount: _asDouble(json['total_amount']),
      paidAmount: _asDouble(json['paid_amount']),
      createdAt: parseServerDateTime(json['created_at'] as String?),
      customerName: customer['name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      customerBalanceAfterSale: _asDouble(customer['balance']),
      createdByName: createdBy['name'] as String? ?? '',
      items: items
          .map((e) => AdminSaleItemModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Price edit ("تعديل سعر") ────────────────────────────────────────────────

class PriceUpdateResultModel {
  final int id;
  final String name;
  final double oldPrice;
  final double newPrice;

  const PriceUpdateResultModel({
    required this.id,
    required this.name,
    required this.oldPrice,
    required this.newPrice,
  });

  factory PriceUpdateResultModel.fromJson(Map<String, dynamic> json) => PriceUpdateResultModel(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        oldPrice: _asDouble(json['old_price']),
        newPrice: _asDouble(json['new_price']),
      );
}

// ─── Inventory count ("عملية جرد") ──────────────────────────────────────────

class InventoryCountItemModel {
  final String itemType; // 'product' | 'raw_material'
  final int? productId;
  final int? rawMaterialId;
  final String name;
  final String unit;
  final double systemQuantity;

  const InventoryCountItemModel({
    required this.itemType,
    required this.productId,
    required this.rawMaterialId,
    required this.name,
    required this.unit,
    required this.systemQuantity,
  });

  factory InventoryCountItemModel.fromJson(Map<String, dynamic> json) => InventoryCountItemModel(
        itemType: json['item_type'] as String? ?? 'product',
        productId: json['product_id'] as int?,
        rawMaterialId: json['raw_material_id'] as int?,
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        systemQuantity: _asDouble(json['system_quantity']),
      );
}

// ─── Vault audit ("جرد الخزائن") ────────────────────────────────────────────
// Mirrors VaultAuditController — same POST /vault-audits the web "جرد
// التصنيع/اللبن" page's جرد الخزائن tab uses (VaultAuditTab in JardPage.tsx).

class VaultAuditModel {
  final int id;
  final String treasuryName;
  final double systemBalance;
  final double physicalBalance;
  final double variance;
  final String? notes;
  final String? performerName;
  final DateTime? createdAt;

  const VaultAuditModel({
    required this.id,
    required this.treasuryName,
    required this.systemBalance,
    required this.physicalBalance,
    required this.variance,
    required this.notes,
    required this.performerName,
    required this.createdAt,
  });

  factory VaultAuditModel.fromJson(Map<String, dynamic> json) {
    final treasury = json['treasury'] as Map<String, dynamic>?;
    final performer = json['performer'] as Map<String, dynamic>?;
    return VaultAuditModel(
      id: json['id'] as int,
      treasuryName: treasury?['name'] as String? ?? '—',
      systemBalance: _asDouble(json['system_balance']),
      physicalBalance: _asDouble(json['physical_balance']),
      variance: _asDouble(json['variance']),
      notes: json['notes'] as String?,
      performerName: performer?['name'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }
}

// ─── Debt audit ("جرد المديونيات" / "جرد ديون الموردين") ───────────────────
// Mirrors DebtAuditController — same POST /debt-audits the web "جرد
// التصنيع/اللبن" page's جرد المديونيات/جرد ديون الموردين tabs use
// (EntityAuditTab in JardPage.tsx), scoped here to client_type in
// (customer, supplier) since the milk variants have no mobile screen.

class DebtAuditModel {
  final int id;
  final String clientType; // 'customer' | 'supplier'
  final String entityName;
  final double systemBalance;
  final double physicalBalance;
  final double variance;
  final String? notes;
  final String? performerName;
  final DateTime? createdAt;

  const DebtAuditModel({
    required this.id,
    required this.clientType,
    required this.entityName,
    required this.systemBalance,
    required this.physicalBalance,
    required this.variance,
    required this.notes,
    required this.performerName,
    required this.createdAt,
  });

  factory DebtAuditModel.fromJson(Map<String, dynamic> json) {
    final performer = json['performer'] as Map<String, dynamic>?;
    final clientType = json['client_type'] as String? ?? 'customer';
    final entity = (json['customer'] ?? json['supplier']) as Map<String, dynamic>?;
    return DebtAuditModel(
      id: json['id'] as int,
      clientType: clientType,
      entityName: entity?['name'] as String? ?? '—',
      systemBalance: _asDouble(json['system_balance']),
      physicalBalance: _asDouble(json['physical_balance']),
      variance: _asDouble(json['variance']),
      notes: json['notes'] as String?,
      performerName: performer?['name'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    );
  }
}

// ─── Settlement history ("سجل التسويات") ────────────────────────────────────

/// Mirrors AdminDelegateController::settlementHistory() — a structured
/// DelegateSettlementRecord row written at the moment a delegate's shift is
/// settled (see settleDelegate()), rather than only ever appearing once in
/// that request's response and as free text in DelegateLoading.notes.
class SettlementRecordModel {
  final int id;
  final int loadingId;
  final String delegateName;
  final DateTime settledAt;
  // Null when genuinely unrecoverable for an old, pre-this-feature
  // settlement — never fabricated, see the backfill command's doc comment.
  final double? grossSales;
  final double expectedCash;
  final double physicalCash;
  final double cashVariance;
  final double walletAmount;
  final String? treasuryName;
  final String? walletTreasuryName;
  final double cashShortageDeduction;
  final double stockShortageDeduction;
  final double damagedGoodsValue;
  final String? settledByName;
  final bool isBackfilled;

  const SettlementRecordModel({
    required this.id,
    required this.loadingId,
    required this.delegateName,
    required this.settledAt,
    required this.grossSales,
    required this.expectedCash,
    required this.physicalCash,
    required this.cashVariance,
    required this.walletAmount,
    required this.treasuryName,
    required this.walletTreasuryName,
    required this.cashShortageDeduction,
    required this.stockShortageDeduction,
    required this.damagedGoodsValue,
    required this.settledByName,
    required this.isBackfilled,
  });

  double get totalDeductions => cashShortageDeduction + stockShortageDeduction;

  factory SettlementRecordModel.fromJson(Map<String, dynamic> json) {
    final delegate = json['delegate'] as Map<String, dynamic>?;
    final treasury = json['treasury'] as Map<String, dynamic>?;
    final walletTreasury = json['wallet_treasury'] as Map<String, dynamic>?;
    final settledBy = json['settled_by'] as Map<String, dynamic>?;
    return SettlementRecordModel(
      id: json['id'] as int,
      loadingId: json['loading_id'] as int? ?? 0,
      delegateName: delegate?['name'] as String? ?? 'غير معروف',
      settledAt: parseServerDateTime(json['settled_at'] as String?),
      grossSales: json['gross_sales'] != null ? _asDouble(json['gross_sales']) : null,
      expectedCash: _asDouble(json['expected_cash']),
      physicalCash: _asDouble(json['physical_cash']),
      cashVariance: _asDouble(json['cash_variance']),
      walletAmount: _asDouble(json['wallet_amount']),
      treasuryName: treasury?['name'] as String?,
      walletTreasuryName: walletTreasury?['name'] as String?,
      cashShortageDeduction: _asDouble(json['cash_shortage_deduction']),
      stockShortageDeduction: _asDouble(json['stock_shortage_deduction']),
      damagedGoodsValue: _asDouble(json['damaged_goods_value']),
      settledByName: settledBy?['name'] as String?,
      isBackfilled: json['is_backfilled'] as bool? ?? false,
    );
  }
}

class SettlementRecordPageModel {
  final List<SettlementRecordModel> data;
  final int currentPage;
  final int lastPage;
  const SettlementRecordPageModel(
      {required this.data, required this.currentPage, required this.lastPage});

  bool get hasMore => currentPage < lastPage;

  factory SettlementRecordPageModel.fromJson(Map<String, dynamic> json) =>
      SettlementRecordPageModel(
        data: (json['data'] as List? ?? [])
            .map((e) => SettlementRecordModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentPage: (json['current_page'] as num? ?? 1).toInt(),
        lastPage: (json['last_page'] as num? ?? 1).toInt(),
      );
}

// ── Indicator trend (switchable dashboard trend-chart widget) ──────────────

class IndicatorTrendPointModel {
  final String date;
  final String label;
  final double value;
  const IndicatorTrendPointModel({required this.date, required this.label, required this.value});

  factory IndicatorTrendPointModel.fromJson(Map<String, dynamic> json) => IndicatorTrendPointModel(
        date: json['date'] as String? ?? '',
        label: json['label'] as String? ?? '',
        value: _asDouble(json['value']),
      );
}

/// Response of GET /admin/indicator-trend — see IndicatorTrendCalculator on
/// the backend (shared with the web dashboard's identical endpoint).
/// isSnapshotBased indicators (رأس المال/المديونيات) only have real
/// historical points from `historicalDataSince` onward — no ledger exists
/// for either metric before that, see the migration's docblock.
class IndicatorTrendModel {
  final bool isSnapshotBased;
  final String? historicalDataSince;
  final List<IndicatorTrendPointModel> data;
  final double currentValue;
  final double? periodTotal;

  const IndicatorTrendModel({
    required this.isSnapshotBased,
    required this.historicalDataSince,
    required this.data,
    required this.currentValue,
    required this.periodTotal,
  });

  factory IndicatorTrendModel.fromJson(Map<String, dynamic> json) => IndicatorTrendModel(
        isSnapshotBased: json['is_snapshot_based'] as bool? ?? false,
        historicalDataSince: json['historical_data_since'] as String?,
        data: (json['data'] as List? ?? [])
            .map((e) => IndicatorTrendPointModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentValue: _asDouble(json['current_value']),
        periodTotal: json['period_total'] == null ? null : _asDouble(json['period_total']),
      );
}

// ─── Daily summary ("ملخص اليوم" / يومية مبيعات) ──────────────────────────

/// Mirrors AdminDelegateController::dailySummary() — see that endpoint's
/// doc comment for what's reused (settlement figures, invoice-level sums)
/// vs newly derived (the per-product منصرف/مباع/رصيد السيارة breakdown).
class DailySummaryProductModel {
  final int productId;
  final String name;
  final String unit;
  final double issuedQty;
  final double soldQty;
  final double unitPrice;
  final double cashTotal;
  final double remainingTruckStock;

  const DailySummaryProductModel({
    required this.productId,
    required this.name,
    required this.unit,
    required this.issuedQty,
    required this.soldQty,
    required this.unitPrice,
    required this.cashTotal,
    required this.remainingTruckStock,
  });

  factory DailySummaryProductModel.fromJson(Map<String, dynamic> json) => DailySummaryProductModel(
        productId: json['product_id'] as int,
        name: json['name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        issuedQty: _asDouble(json['issued_qty']),
        soldQty: _asDouble(json['sold_qty']),
        unitPrice: _asDouble(json['unit_price']),
        cashTotal: _asDouble(json['cash_total']),
        remainingTruckStock: _asDouble(json['remaining_truck_stock']),
      );
}

class DailySummaryCollectionModel {
  final String customer;
  final double amount;
  const DailySummaryCollectionModel({required this.customer, required this.amount});
  factory DailySummaryCollectionModel.fromJson(Map<String, dynamic> json) =>
      DailySummaryCollectionModel(
        customer: json['customer'] as String? ?? 'غير معروف',
        amount: _asDouble(json['amount']),
      );
}

class DailySummaryDebtInvoiceModel {
  final String customer;
  final double amount;
  final String invoiceNumber;
  const DailySummaryDebtInvoiceModel({
    required this.customer,
    required this.amount,
    required this.invoiceNumber,
  });
  factory DailySummaryDebtInvoiceModel.fromJson(Map<String, dynamic> json) =>
      DailySummaryDebtInvoiceModel(
        customer: json['customer'] as String? ?? 'غير معروف',
        amount: _asDouble(json['amount']),
        invoiceNumber: json['invoice_number'] as String? ?? '',
      );
}

class DailySummaryReplacementModel {
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double value;
  const DailySummaryReplacementModel({
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.value,
  });
  factory DailySummaryReplacementModel.fromJson(Map<String, dynamic> json) =>
      DailySummaryReplacementModel(
        productName: json['product_name'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        quantity: _asDouble(json['quantity']),
        unitPrice: _asDouble(json['unit_price']),
        value: _asDouble(json['value']),
      );
}

class DailySummaryReturnModel {
  final String customer;
  final String product;
  final String unit;
  final double quantity;
  final double value;
  final String condition;
  // 'cash' or 'in_kind_replacement' — see DelegateInvoiceReturn.refund_method.
  final String refundMethod;
  final DailySummaryReplacementModel? replacement;

  const DailySummaryReturnModel({
    required this.customer,
    required this.product,
    required this.unit,
    required this.quantity,
    required this.value,
    required this.condition,
    required this.refundMethod,
    required this.replacement,
  });

  factory DailySummaryReturnModel.fromJson(Map<String, dynamic> json) => DailySummaryReturnModel(
        customer: json['customer'] as String? ?? 'غير معروف',
        product: json['product'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        quantity: _asDouble(json['quantity']),
        value: _asDouble(json['value']),
        condition: json['condition'] as String? ?? '',
        refundMethod: json['refund_method'] as String? ?? 'cash',
        replacement: json['replacement'] != null
            ? DailySummaryReplacementModel.fromJson(json['replacement'] as Map<String, dynamic>)
            : null,
      );
}

class DailySummaryExpenseModel {
  final String description;
  final double amount;
  const DailySummaryExpenseModel({required this.description, required this.amount});
  factory DailySummaryExpenseModel.fromJson(Map<String, dynamic> json) => DailySummaryExpenseModel(
        description: json['description'] as String? ?? '',
        amount: _asDouble(json['amount']),
      );
}

class DailySummaryCashRowModel {
  final double? grossSales;
  final double? totalCollections;
  final double? totalExpenses;
  final double totalReturns;
  final double totalDebtAdded;
  final double expectedCash;
  final double walletAmount;
  final double cashVariance;

  const DailySummaryCashRowModel({
    required this.grossSales,
    required this.totalCollections,
    required this.totalExpenses,
    required this.totalReturns,
    required this.totalDebtAdded,
    required this.expectedCash,
    required this.walletAmount,
    required this.cashVariance,
  });

  factory DailySummaryCashRowModel.fromJson(Map<String, dynamic> json) => DailySummaryCashRowModel(
        grossSales: json['gross_sales'] == null ? null : _asDouble(json['gross_sales']),
        totalCollections:
            json['total_collections'] == null ? null : _asDouble(json['total_collections']),
        totalExpenses: json['total_expenses'] == null ? null : _asDouble(json['total_expenses']),
        totalReturns: _asDouble(json['total_returns']),
        totalDebtAdded: _asDouble(json['total_debt_added']),
        expectedCash: _asDouble(json['expected_cash']),
        walletAmount: _asDouble(json['wallet_amount']),
        cashVariance: _asDouble(json['cash_variance']),
      );
}

class DailySummaryModel {
  final int settlementId;
  final int loadingId;
  final String delegateName;
  final DateTime settledAt;
  final DateTime? loadedAt;
  final bool isBackfilled;
  final DailySummaryCashRowModel summary;
  final List<DailySummaryProductModel> products;
  final List<DailySummaryCollectionModel> collections;
  final List<DailySummaryDebtInvoiceModel> debtInvoices;
  final List<DailySummaryReturnModel> returns;
  final List<DailySummaryExpenseModel> expenses;

  const DailySummaryModel({
    required this.settlementId,
    required this.loadingId,
    required this.delegateName,
    required this.settledAt,
    required this.loadedAt,
    required this.isBackfilled,
    required this.summary,
    required this.products,
    required this.collections,
    required this.debtInvoices,
    required this.returns,
    required this.expenses,
  });

  factory DailySummaryModel.fromJson(Map<String, dynamic> json) {
    final settlement = json['settlement'] as Map<String, dynamic>;
    final delegate = settlement['delegate'] as Map<String, dynamic>?;
    return DailySummaryModel(
      settlementId: settlement['id'] as int,
      loadingId: settlement['loading_id'] as int,
      delegateName: delegate?['name'] as String? ?? 'غير معروف',
      settledAt: parseServerDateTime(settlement['settled_at'] as String?),
      loadedAt: settlement['loaded_at'] != null
          ? parseServerDateTime(settlement['loaded_at'] as String?)
          : null,
      isBackfilled: settlement['is_backfilled'] as bool? ?? false,
      summary: DailySummaryCashRowModel.fromJson(json['summary'] as Map<String, dynamic>),
      products: (json['products'] as List? ?? [])
          .map((e) => DailySummaryProductModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      collections: (json['collections'] as List? ?? [])
          .map((e) => DailySummaryCollectionModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      debtInvoices: (json['debt_invoices'] as List? ?? [])
          .map((e) => DailySummaryDebtInvoiceModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      returns: (json['returns'] as List? ?? [])
          .map((e) => DailySummaryReturnModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      expenses: (json['expenses'] as List? ?? [])
          .map((e) => DailySummaryExpenseModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
