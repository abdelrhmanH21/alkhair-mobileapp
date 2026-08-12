import '../../../../core/utils/date_parsing.dart';

class InvoiceSaleItem {
  final int productId;
  final String productName;
  final double maxQty;
  double quantity;
  final double unitPrice;
  double get subtotal => quantity * unitPrice;

  InvoiceSaleItem({
    required this.productId,
    required this.productName,
    this.maxQty = double.infinity,
    this.quantity = 1,
    this.unitPrice = 0,
  });
}

class InvoiceReturnItem {
  final int productId;
  final String productName;
  double quantity;
  final double unitPrice;
  String condition; // 'سليم' | 'تالف'
  // How the customer was compensated for this return — 'cash' (reduces
  // cash owed, same as always) or 'in_kind_replacement' (a different
  // truck-stock product handed over instead; see replacement* fields
  // below and DelegateInvoiceController::store()'s net_total formula).
  String refundMethod;
  int? replacementProductId;
  String? replacementProductName;
  double? replacementQuantity;
  double? replacementUnitPrice;
  double get subtotal => quantity * unitPrice;
  double? get replacementSubtotal =>
      (replacementQuantity != null && replacementUnitPrice != null)
          ? replacementQuantity! * replacementUnitPrice!
          : null;

  InvoiceReturnItem({
    required this.productId,
    required this.productName,
    this.quantity = 1,
    this.unitPrice = 0,
    this.condition = 'سليم',
    this.refundMethod = 'cash',
    this.replacementProductId,
    this.replacementProductName,
    this.replacementQuantity,
    this.replacementUnitPrice,
  });
}

/// Pure net-total formula for a delegate invoice — mirrors
/// DelegateInvoiceController::store()'s server-side computation exactly
/// (`grossSales - discount - totalReturns + replacementItemsTotal`) so the
/// totals card shown before submit always matches what the server will
/// actually persist.
///
/// [totalReturns] is the full value of EVERY return regardless of
/// refund_method (unchanged meaning — "value of goods that came back").
/// [replacementItemsTotal] is only the sum of in-kind-replacement returns'
/// replacement-product value, ADDED back on top: a cash-refund return's
/// value already reduces net total via totalReturns as always; an
/// in-kind-replacement return's own value does too, but is deliberately
/// offset back out here by the replacement product's own value, since no
/// cash left the till for that swap — net effect of an in-kind swap =
/// replacement value − returned value (zero when they're equal).
double computeInvoiceNetTotal({
  required double grossSales,
  required double discountAmount,
  required double totalReturns,
  required double replacementItemsTotal,
}) =>
    grossSales - discountAmount - totalReturns + replacementItemsTotal;

class DelegateInvoiceModel {
  final int id;
  final String invoiceNumber;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final double grossSalesTotal;
  final double discountAmount;
  final double totalReturns;
  final double netTotal;
  final double cashReceived;
  final double balanceAddedToDebt;
  final double debtReduction;
  final double customerBalance;
  final DateTime createdAt;

  const DelegateInvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.grossSalesTotal,
    this.discountAmount = 0,
    required this.totalReturns,
    required this.netTotal,
    required this.cashReceived,
    required this.balanceAddedToDebt,
    this.debtReduction = 0,
    this.customerBalance = 0,
    required this.createdAt,
  });

  factory DelegateInvoiceModel.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? {};
    return DelegateInvoiceModel(
      id: json['id'] as int,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      customerId: json['customer_id'] as int,
      customerName: customer['name'] as String? ?? '',
      customerPhone: customer['phone'] as String? ?? '',
      grossSalesTotal: (json['gross_sales_total'] as num? ?? 0).toDouble(),
      discountAmount: (json['discount_amount'] as num? ?? 0).toDouble(),
      totalReturns: (json['total_returns'] as num? ?? 0).toDouble(),
      netTotal: (json['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (json['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt: (json['balance_added_to_debt'] as num? ?? 0).toDouble(),
      debtReduction: (json['debt_reduction'] as num? ?? 0).toDouble(),
      customerBalance: (customer['balance'] as num? ?? 0).toDouble(),
      createdAt: parseServerDateTime(json['created_at'] as String?),
    );
  }
}
