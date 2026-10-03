import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';

/// Covers the mobile-side models for the "مندوب حر السعر" (free-pricing
/// delegate) feature: UserModel's new isFreePricingDelegate flag (drives
/// dashboard_section.dart's branch), PayrollSummaryRowModel's matching
/// fields (drives admin_payroll_page.dart's alternate detail view), and the
/// self-service price-variance summary parsing (DelegateDashboardController
/// ::priceVarianceSummary()'s actual response shape).
void main() {
  group('UserModel.fromJson — is_free_pricing_delegate', () {
    test('parses true when present', () {
      final user = UserModel.fromJson({
        'id': 1, 'name': 'طارق', 'email': 't@test.local', 'role': 'delegate',
        'is_active': true, 'permissions': [], 'has_active_loading': false,
        'truck_stock_count': 0, 'is_free_pricing_delegate': true,
      });
      expect(user.isFreePricingDelegate, isTrue);
    });

    test('defaults to false when absent (older/other endpoints)', () {
      final user = UserModel.fromJson({
        'id': 2, 'name': 'مندوب عادي', 'email': 'n@test.local', 'role': 'delegate',
        'is_active': true, 'permissions': [], 'has_active_loading': false,
        'truck_stock_count': 0,
      });
      expect(user.isFreePricingDelegate, isFalse);
    });
  });

  group('PayrollSummaryRowModel.fromJson — free-pricing fields', () {
    test('parses is_free_pricing_delegate and price_variance_balance', () {
      final row = PayrollSummaryRowModel.fromJson({
        'rep_id': 5, 'rep_name': 'طارق', 'phone': null,
        'monthly_target': 0, 'achieved_this_month': 0, 'target_percentage': null,
        'commission_earned': 0, 'penalties_total': 0, 'advances_total': 0, 'bonus_total': 0,
        'net_payable': 0, 'has_linked_user': true,
        'is_free_pricing_delegate': true, 'price_variance_balance': '135.50',
      });
      expect(row.isFreePricingDelegate, isTrue);
      expect(row.priceVarianceBalance, 135.50);
    });

    test('defaults to not-free-pricing / zero balance when absent', () {
      final row = PayrollSummaryRowModel.fromJson({
        'rep_id': 6, 'rep_name': 'مندوب عادي', 'phone': null,
        'monthly_target': 0, 'achieved_this_month': 0, 'target_percentage': null,
        'commission_earned': 0, 'penalties_total': 0, 'advances_total': 0, 'bonus_total': 0,
        'net_payable': 0, 'has_linked_user': false,
      });
      expect(row.isFreePricingDelegate, isFalse);
      expect(row.priceVarianceBalance, 0);
    });
  });

  group('ReferencePriceSaveResult.fromJson — retroactive recompute payload', () {
    test('parses the recompute summary when prices changed (265 -> 255 example: 95 -> 145)', () {
      final r = ReferencePriceSaveResult.fromJson({
        'data': [],
        'variance_recalculation': {
          'invoices_recalculated': 2,
          'balance_before': 95,
          'balance_after': 145.0,
          'changes': [],
        },
      });
      expect(r.invoicesRecalculated, 2);
      expect(r.balanceBefore, 95.0);
      expect(r.balanceAfter, 145.0);
    });

    test('is a no-op result when nothing changed (variance_recalculation null)', () {
      final r = ReferencePriceSaveResult.fromJson({'data': [], 'variance_recalculation': null});
      expect(r.invoicesRecalculated, 0);
      expect(r.balanceBefore, isNull);
      expect(r.balanceAfter, isNull);
    });
  });
}
