import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/price_variance_models.dart';
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

  group('PriceVarianceSummaryModel.fromJson', () {
    test('parses balance + by-loading breakdown with per-line variance', () {
      final model = PriceVarianceSummaryModel.fromJson({
        'price_variance_balance': 70.0,
        'by_loading': [
          {
            'loading_id': 3,
            'date': '2026-09-20',
            'status': 'in_transit',
            'loading_variance_total': 70.0,
            'lines': [
              {
                'invoice_id': 12, 'invoice_number': 'DINV-000012',
                'customer_name': 'عميل تجريبي', 'product_name': 'جبنة',
                'quantity': 2, 'reference_price': 265.0, 'charged_price': 300.0, 'variance': 70.0,
              },
            ],
          },
          // A loading with zero sold lines (e.g. just picked up) — backend
          // filters these out of by_loading entirely, but the model must
          // still parse an empty list gracefully if one ever arrives.
          {'loading_id': 4, 'date': '2026-09-21', 'status': 'accepted', 'loading_variance_total': 0, 'lines': []},
        ],
      });

      expect(model.priceVarianceBalance, 70.0);
      expect(model.byLoading, hasLength(2));

      final first = model.byLoading.first;
      expect(first.loadingId, 3);
      expect(first.loadingVarianceTotal, 70.0);
      expect(first.lines, hasLength(1));

      final line = first.lines.first;
      expect(line.customerName, 'عميل تجريبي');
      expect(line.productName, 'جبنة');
      expect(line.quantity, 2.0);
      expect(line.referencePrice, 265.0);
      expect(line.chargedPrice, 300.0);
      expect(line.variance, 70.0);

      expect(model.byLoading.last.lines, isEmpty);
    });

    test('parses cleanly with no loadings at all (brand-new free-pricing rep)', () {
      final model = PriceVarianceSummaryModel.fromJson({
        'price_variance_balance': 0,
        'by_loading': [],
      });
      expect(model.priceVarianceBalance, 0);
      expect(model.byLoading, isEmpty);
    });
  });
}
