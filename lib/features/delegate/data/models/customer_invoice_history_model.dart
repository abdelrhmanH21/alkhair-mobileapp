/// Mirrors DelegateInvoiceController::customerHistory() rows — a customer's
/// full purchase history across ALL delegates who ever served them, not just
/// the currently authenticated one.
class CustomerInvoiceHistorySummaryModel {
  final int totalInvoicesCount;
  final double totalPurchased;
  final double currentBalance;

  const CustomerInvoiceHistorySummaryModel({
    required this.totalInvoicesCount,
    required this.totalPurchased,
    required this.currentBalance,
  });

  factory CustomerInvoiceHistorySummaryModel.fromJson(Map<String, dynamic> json) =>
      CustomerInvoiceHistorySummaryModel(
        totalInvoicesCount: (json['total_invoices_count'] as num? ?? 0).toInt(),
        totalPurchased: (json['total_purchased'] as num? ?? 0).toDouble(),
        currentBalance: (json['current_balance'] as num? ?? 0).toDouble(),
      );
}

class CustomerInvoiceHistoryRowModel {
  final int id;
  final String invoiceNumber;
  final DateTime date;
  final double netTotal;
  final double cashReceived;
  final double debtReduction;
  final double balanceAddedToDebt;
  final String delegateName;
  final String status;

  const CustomerInvoiceHistoryRowModel({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    required this.netTotal,
    required this.cashReceived,
    required this.debtReduction,
    required this.balanceAddedToDebt,
    required this.delegateName,
    required this.status,
  });

  factory CustomerInvoiceHistoryRowModel.fromJson(Map<String, dynamic> json) {
    final delegate = json['delegate'] as Map<String, dynamic>? ?? {};
    return CustomerInvoiceHistoryRowModel(
      id: json['id'] as int,
      invoiceNumber: json['invoice_number'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      netTotal: (json['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (json['cash_received'] as num? ?? 0).toDouble(),
      debtReduction: (json['debt_reduction'] as num? ?? 0).toDouble(),
      balanceAddedToDebt: (json['balance_added_to_debt'] as num? ?? 0).toDouble(),
      delegateName: delegate['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
    );
  }
}

class CustomerInvoiceHistoryModel {
  final CustomerInvoiceHistorySummaryModel summary;
  final List<CustomerInvoiceHistoryRowModel> rows;
  final int currentPage;
  final int lastPage;

  const CustomerInvoiceHistoryModel({
    required this.summary,
    required this.rows,
    required this.currentPage,
    required this.lastPage,
  });

  bool get hasMore => currentPage < lastPage;

  factory CustomerInvoiceHistoryModel.fromJson(Map<String, dynamic> json) {
    final rowsJson = json['data'] as List? ?? [];
    return CustomerInvoiceHistoryModel(
      summary: CustomerInvoiceHistorySummaryModel.fromJson(
          json['summary'] as Map<String, dynamic>? ?? {}),
      rows: rowsJson
          .map((e) => CustomerInvoiceHistoryRowModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPage: (json['current_page'] as num? ?? 1).toInt(),
      lastPage: (json['last_page'] as num? ?? 1).toInt(),
    );
  }
}
