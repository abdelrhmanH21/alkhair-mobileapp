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

/// One row of كشف حساب عميل — mirrors CustomerDebtLedger::present().
/// [amount] is signed (+ adds to the debt, − reduces it); [balanceAfter]
/// is the running debt right after this row. type is one of opening,
/// carried_forward, invoice, sale, collection, return, debt_audit,
/// unexplained.
class CustomerLedgerRowModel {
  final String type;
  final String typeLabel;
  final String date;
  final String? invoiceNumber;
  final String? actor;
  final String description;
  final double amount;
  final double balanceAfter;
  final double? oldValue;
  final double? newValue;
  final String? notes;

  const CustomerLedgerRowModel({
    required this.type,
    required this.typeLabel,
    required this.date,
    this.invoiceNumber,
    this.actor,
    required this.description,
    required this.amount,
    required this.balanceAfter,
    this.oldValue,
    this.newValue,
    this.notes,
  });

  bool get isBalanceMarker => type == 'opening' || type == 'carried_forward';

  factory CustomerLedgerRowModel.fromJson(Map<String, dynamic> json) => CustomerLedgerRowModel(
        type: json['type'] as String? ?? '',
        typeLabel: json['type_label'] as String? ?? '',
        date: json['date'] as String? ?? '',
        invoiceNumber: json['invoice_number'] as String?,
        actor: json['actor'] as String?,
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        balanceAfter: (json['balance_after'] as num? ?? 0).toDouble(),
        oldValue: (json['old_value'] as num?)?.toDouble(),
        newValue: (json['new_value'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
      );
}

/// Mirrors CompanyReportController::customerStatement() (كشف حساب عميل,
/// admin/manager only). Rows are chronological; the last row's
/// balance_after equals [currentBalance] unless a date_to cut it short
/// (then it's [closingBalance], the balance at the end of the period).
class CustomerLedgerModel {
  final int customerId;
  final String customerName;
  final String? customerPhone;
  final String? periodFrom;
  final String? periodTo;
  final List<CustomerLedgerRowModel> rows;
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
  final double currentBalance;
  final double unexplainedTotal;

  const CustomerLedgerModel({
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.periodFrom,
    this.periodTo,
    required this.rows,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.currentBalance,
    required this.unexplainedTotal,
  });

  factory CustomerLedgerModel.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? const {};
    final period = json['period'] as Map<String, dynamic>? ?? const {};
    final summary = json['summary'] as Map<String, dynamic>? ?? const {};
    double n(String k) => (summary[k] as num? ?? 0).toDouble();
    return CustomerLedgerModel(
      customerId: customer['id'] as int? ?? 0,
      customerName: customer['name'] as String? ?? '',
      customerPhone: customer['phone'] as String?,
      periodFrom: period['from'] as String?,
      periodTo: period['to'] as String?,
      rows: (json['data'] as List? ?? [])
          .map((e) => CustomerLedgerRowModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      openingBalance: n('opening_balance'),
      totalDebit: n('total_debit'),
      totalCredit: n('total_credit'),
      closingBalance: n('closing_balance'),
      currentBalance: n('current_balance'),
      unexplainedTotal: n('unexplained_total'),
    );
  }

  bool get isFullHistory => periodFrom == null && periodTo == null;
}
