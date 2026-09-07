import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/breakdown_models.dart';

/// Covers the JSON parsing added for Part 1 (bonus deletion) and Part 2
/// (manual commission override) of the payroll task:
///  - PayrollSummaryRowModel.isCommissionOverridden/computedCommissionEarned
///    (AdminDelegateController::payrollSummary()'s new response fields).
///  - BonusModel.isApplied (DelegateDashboardController::bonuses()'s new
///    field), which gates whether the "حذف" button shows in the bonus tab.
void main() {
  group('PayrollSummaryRowModel.fromJson — commission override fields', () {
    Map<String, dynamic> baseJson({
      bool? isOverridden,
      double? computed,
    }) => {
          'rep_id': 1,
          'rep_name': 'مندوب اختبار',
          'phone': null,
          'monthly_target': 1000,
          'achieved_this_month': 500,
          'target_percentage': 50,
          'commission_earned': 900,
          'penalties_total': 0,
          'advances_total': 0,
          'bonus_total': 0,
          'net_payable': 3900,
          'has_linked_user': false,
          if (isOverridden != null) 'is_commission_overridden': isOverridden,
          if (computed != null) 'computed_commission_earned': computed,
        };

    test('parses is_commission_overridden=true and computed_commission_earned', () {
      final model = PayrollSummaryRowModel.fromJson(
        baseJson(isOverridden: true, computed: 500),
      );
      expect(model.isCommissionOverridden, isTrue);
      expect(model.commissionEarned, 900.0);
      expect(model.computedCommissionEarned, 500.0);
    });

    test('defaults to not-overridden when the field is absent (older/other endpoints)', () {
      final model = PayrollSummaryRowModel.fromJson(baseJson());
      expect(model.isCommissionOverridden, isFalse);
      // Falls back to commission_earned itself when computed_commission_earned
      // is missing, so a screen reading this field never crashes on null.
      expect(model.computedCommissionEarned, model.commissionEarned);
    });

    test('is_commission_overridden=false with a distinct computed value', () {
      final model = PayrollSummaryRowModel.fromJson(
        baseJson(isOverridden: false, computed: 900),
      );
      expect(model.isCommissionOverridden, isFalse);
      expect(model.computedCommissionEarned, 900.0);
    });
  });

  group('BonusModel.fromJson — is_applied gating', () {
    test('parses is_applied=true (already folded into a paid payroll record)', () {
      final model = BonusModel.fromJson({
        'id': 5,
        'date': '2026-06-10',
        'amount': 200,
        'reason': 'مكافأة أداء',
        'is_applied': true,
      });
      expect(model.isApplied, isTrue);
      expect(model.amount, 200.0);
    });

    test('defaults is_applied to false when absent', () {
      final model = BonusModel.fromJson({
        'id': 6,
        'date': '2026-06-11',
        'amount': 100,
        'reason': null,
      });
      expect(model.isApplied, isFalse);
    });
  });
}
