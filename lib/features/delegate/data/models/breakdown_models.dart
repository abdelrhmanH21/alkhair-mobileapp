/// Mirrors DelegateDashboardController::penalties() rows.
class PenaltyModel {
  final int id;
  final String date;
  final double amount;
  final String reason;

  const PenaltyModel({
    required this.id,
    required this.date,
    required this.amount,
    required this.reason,
  });

  factory PenaltyModel.fromJson(Map<String, dynamic> json) => PenaltyModel(
        id: json['id'] as int,
        date: json['date'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        reason: json['reason'] as String? ?? '',
      );
}

/// Mirrors DelegateDashboardController::advances() rows.
class AdvanceModel {
  final int id;
  final String date;
  final double amount;
  final String type;
  final String? description;

  const AdvanceModel({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    this.description,
  });

  factory AdvanceModel.fromJson(Map<String, dynamic> json) => AdvanceModel(
        id: json['id'] as int,
        date: json['date'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        type: json['type'] as String? ?? '',
        description: json['description'] as String?,
      );
}

/// Mirrors DelegateDashboardController::commissionBreakdown() rows — one
/// per calendar day with at least one invoice.
class CommissionDayModel {
  final String date;
  final double totalSales;
  final double commissionEarned;

  const CommissionDayModel({
    required this.date,
    required this.totalSales,
    required this.commissionEarned,
  });

  factory CommissionDayModel.fromJson(Map<String, dynamic> json) => CommissionDayModel(
        date: json['date'] as String? ?? '',
        totalSales: (json['total_sales'] as num? ?? 0).toDouble(),
        commissionEarned: (json['commission_earned'] as num? ?? 0).toDouble(),
      );
}
