/// Mirrors DelegateDashboardController::penalties() rows.
class PenaltyModel {
  final int id;
  final String date;
  final double amount;
  final String reason;
  // True for a "مندوب حر السعر" rep's record: it moved price_variance_balance
  // (المستحق) instead of being a payroll deduction/addition.
  final bool redirectedToPriceVariance;

  const PenaltyModel({
    required this.id,
    required this.date,
    required this.amount,
    required this.reason,
    this.redirectedToPriceVariance = false,
  });

  factory PenaltyModel.fromJson(Map<String, dynamic> json) => PenaltyModel(
        id: json['id'] as int,
        date: json['date'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        reason: json['reason'] as String? ?? '',
        redirectedToPriceVariance: json['redirected_to_price_variance'] as bool? ?? false,
      );
}

/// Mirrors DelegateDashboardController::advances() rows.
class AdvanceModel {
  final int id;
  final String date;
  final double amount;
  final String type;
  final String? description;
  // True for a "مندوب حر السعر" rep's record: it moved price_variance_balance
  // (المستحق) instead of being a payroll deduction/addition.
  final bool redirectedToPriceVariance;

  const AdvanceModel({
    required this.id,
    required this.date,
    required this.amount,
    required this.type,
    this.description,
    this.redirectedToPriceVariance = false,
  });

  factory AdvanceModel.fromJson(Map<String, dynamic> json) => AdvanceModel(
        id: json['id'] as int,
        date: json['date'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        type: json['type'] as String? ?? '',
        description: json['description'] as String?,
        redirectedToPriceVariance: json['redirected_to_price_variance'] as bool? ?? false,
      );
}

/// Mirrors DelegateDashboardController::bonuses() rows.
class BonusModel {
  final int id;
  final String date;
  final double amount;
  final String? reason;
  // Whether this bonus has already been folded into a paid payroll record —
  // once true it's frozen and can no longer be deleted (mirrors Penalty/
  // Advance's is_applied/is_deducted gating on the web delete buttons).
  final bool isApplied;
  // True for a "مندوب حر السعر" rep's record: it moved price_variance_balance
  // (المستحق) instead of being a payroll deduction/addition.
  final bool redirectedToPriceVariance;

  const BonusModel({
    required this.id,
    required this.date,
    required this.amount,
    this.reason,
    this.isApplied = false,
    this.redirectedToPriceVariance = false,
  });

  factory BonusModel.fromJson(Map<String, dynamic> json) => BonusModel(
        id: json['id'] as int,
        date: json['date'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        reason: json['reason'] as String?,
        isApplied: json['is_applied'] as bool? ?? false,
        redirectedToPriceVariance: json['redirected_to_price_variance'] as bool? ?? false,
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
