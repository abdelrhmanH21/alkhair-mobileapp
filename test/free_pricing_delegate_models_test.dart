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

  group('effective-dated reference prices — admin payloads', () {
    test('ReferencePriceProductModel parses the price effective today, the schedule and the history', () {
      final m = ReferencePriceProductModel.fromJson({
        'product_id': 7,
        'product_name': 'جبن',
        'unit': 'kg',
        'has_price': true,
        'version_id': 12,
        'reference_price': 35,
        'effective_from': '2026-10-26',
        'next_change': {'reference_price': '40.50', 'effective_from': '2026-11-01'},
        'versions': [
          {'id': 13, 'reference_price': 40.5, 'effective_from': '2026-11-01', 'created_by': {'id': 1, 'name': 'Admin'}, 'created_at': '2026-10-26T10:00:00+03:00'},
          {'id': 12, 'reference_price': 35, 'effective_from': '2026-10-26', 'created_by': null, 'created_at': null},
          {'id': 3, 'reference_price': 20, 'effective_from': null, 'created_by': null, 'created_at': null},
        ],
      });
      expect(m.hasPrice, isTrue);
      expect(m.referencePrice, 35.0);
      expect(m.effectiveFrom, '2026-10-26');
      expect(m.nextChangePrice, 40.5);
      expect(m.nextChangeFrom, '2026-11-01');
      expect(m.versions.map((v) => v.id), [13, 12, 3]);
      expect(m.versions.first.createdByName, 'Admin');
      expect(m.versions.last.effectiveFrom, isNull); // منذ البداية
    });

    test('a product with no price parses with hasPrice=false and null price', () {
      final m = ReferencePriceProductModel.fromJson({
        'product_id': 8, 'product_name': 'لبن', 'unit': 'l', 'has_price': false,
        'reference_price': null, 'effective_from': null, 'next_change': null, 'versions': [],
      });
      expect(m.hasPrice, isFalse);
      expect(m.referencePrice, isNull);
      expect(m.versions, isEmpty);
    });

    test('ReferencePriceChangeResult reads the preview/save payload under data', () {
      final r = ReferencePriceChangeResult.fromJson({
        'message': 'تم حفظ السعر المرجعي الجديد.',
        'data': {
          'invoices_recalculated': 2, 'date_from': '2026-10-22', 'date_to': '2026-10-24',
          'balance_before': 200, 'balance_after': '170.00', 'retroactive': true,
        },
      });
      expect(r.invoicesRecalculated, 2);
      expect(r.dateFrom, '2026-10-22');
      expect(r.balanceBefore, 200.0);
      expect(r.balanceAfter, 170.0);
      expect(r.retroactive, isTrue);
      expect(r.message, 'تم حفظ السعر المرجعي الجديد.');
    });

    test('statement accrual rows carry the applied historical price per line', () {
      final tx = PriceVarianceTransactionModel.fromJson({
        'id': 1, 'type': 'accrual', 'amount': 10, 'balance_after': 10, 'created_at': '2026-10-25T10:00:00',
        'price_date': '2026-10-25',
        'lines': [
          {'product_name': 'جبن', 'quantity': 1, 'reference_price': 20, 'reference_missing': false, 'charged_price': 30, 'variance': 10},
        ],
      });
      expect(tx.priceDate, '2026-10-25');
      expect(tx.lines.single.referencePrice, 20.0);
      expect(tx.lines.single.variance, 10.0);
      // Older server responses without lines still parse.
      final old = PriceVarianceTransactionModel.fromJson({'id': 2, 'type': 'payout', 'amount': -5, 'balance_after': 5, 'created_at': '2026-10-25T10:00:00'});
      expect(old.lines, isEmpty);
    });
  });
}
