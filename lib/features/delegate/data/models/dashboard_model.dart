class DashboardModel {
  final double monthlyTarget;
  final double achievedThisMonth;
  final double? targetPercentage;
  final double commissionEarned;
  final double baseSalary;
  final double penaltiesTotal;
  final double advancesTotal;
  final double netPayable;
  final String currentMonth;

  const DashboardModel({
    required this.monthlyTarget,
    required this.achievedThisMonth,
    required this.targetPercentage,
    required this.commissionEarned,
    required this.baseSalary,
    required this.penaltiesTotal,
    required this.advancesTotal,
    required this.netPayable,
    required this.currentMonth,
  });

  factory DashboardModel.fromJson(Map<String, dynamic> json) {
    return DashboardModel(
      monthlyTarget: (json['monthly_target'] as num? ?? 0).toDouble(),
      achievedThisMonth: (json['achieved_this_month'] as num? ?? 0).toDouble(),
      targetPercentage: (json['target_percentage'] as num?)?.toDouble(),
      commissionEarned: (json['commission_earned'] as num? ?? 0).toDouble(),
      baseSalary: (json['base_salary'] as num? ?? 0).toDouble(),
      penaltiesTotal: (json['penalties_total'] as num? ?? 0).toDouble(),
      advancesTotal: (json['advances_total'] as num? ?? 0).toDouble(),
      netPayable: (json['net_payable'] as num? ?? 0).toDouble(),
      currentMonth: json['current_month'] as String? ?? '',
    );
  }
}
