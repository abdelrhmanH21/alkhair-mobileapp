/// Mirrors DelegateExpenseController::index()/update() rows — this
/// delegate's own expenses for their current active loading.
class ExpenseRecordModel {
  final int id;
  final String description;
  final double amount;
  final String? categoryName;
  final String? notes;
  final DateTime createdAt;

  const ExpenseRecordModel({
    required this.id,
    required this.description,
    required this.amount,
    this.categoryName,
    this.notes,
    required this.createdAt,
  });

  factory ExpenseRecordModel.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return ExpenseRecordModel(
      id: json['id'] as int,
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num? ?? 0).toDouble(),
      categoryName: category?['name'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Mirrors DelegateCustomerCollectionController::index()/update() rows —
/// this delegate's own customer collections for their current active
/// loading, with the customer name included.
class CustomerCollectionRecordModel {
  final int id;
  final int customerId;
  final String customerName;
  final double amount;
  final String? notes;
  final DateTime createdAt;

  const CustomerCollectionRecordModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.amount,
    this.notes,
    required this.createdAt,
  });

  factory CustomerCollectionRecordModel.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>? ?? {};
    return CustomerCollectionRecordModel(
      id: json['id'] as int,
      customerId: json['customer_id'] as int,
      customerName: customer['name'] as String? ?? '',
      amount: (json['amount'] as num? ?? 0).toDouble(),
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
