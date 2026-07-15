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
  double get subtotal => quantity * unitPrice;

  InvoiceReturnItem({
    required this.productId,
    required this.productName,
    this.quantity = 1,
    this.unitPrice = 0,
    this.condition = 'سليم',
  });
}

class DelegateInvoiceModel {
  final int id;
  final String invoiceNumber;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final double grossSalesTotal;
  final double totalReturns;
  final double netTotal;
  final double cashReceived;
  final double balanceAddedToDebt;
  final double debtReduction;
  final DateTime createdAt;

  const DelegateInvoiceModel({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.grossSalesTotal,
    required this.totalReturns,
    required this.netTotal,
    required this.cashReceived,
    required this.balanceAddedToDebt,
    this.debtReduction = 0,
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
      totalReturns: (json['total_returns'] as num? ?? 0).toDouble(),
      netTotal: (json['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (json['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt: (json['balance_added_to_debt'] as num? ?? 0).toDouble(),
      debtReduction: (json['debt_reduction'] as num? ?? 0).toDouble(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
