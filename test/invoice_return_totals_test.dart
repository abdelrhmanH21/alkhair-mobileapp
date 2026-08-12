import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/invoice_model.dart';

/// computeInvoiceNetTotal is the single client-side formula the invoice
/// totals card uses (see invoice_page.dart's _netTotal getter) — it mirrors
/// DelegateInvoiceController::store()'s server-side computation exactly:
///   net_total = gross_sales - discount - total_returns + replacement_items_total
/// These tests pin the three scenarios the "المرتجع" (customer return with
/// refund_method) feature is built around.
void main() {
  group('computeInvoiceNetTotal — refund_method math', () {
    test('cash refund: unchanged from the pre-existing formula (no replacement contribution)', () {
      // A plain sale (100) with a cash-refunded return (20) — same as
      // every return before this feature existed: net_total = gross -
      // discount - returns, full stop.
      final withCashReturn = computeInvoiceNetTotal(
        grossSales: 100,
        discountAmount: 0,
        totalReturns: 20,
        replacementItemsTotal: 0, // no in-kind returns on this invoice
      );
      expect(withCashReturn, 80);

      // Sanity: identical to the literal old formula (gross - discount - returns).
      const oldFormula = 100 - 0 - 20;
      expect(withCashReturn, oldFormula);

      // A discount on top still behaves exactly as before.
      final withDiscountToo = computeInvoiceNetTotal(
        grossSales: 100,
        discountAmount: 10,
        totalReturns: 20,
        replacementItemsTotal: 0,
      );
      expect(withDiscountToo, 70);
    });

    test('in-kind replacement with EQUAL replacement value: nets to zero change '
        'vs. an invoice with no return/replacement at all', () {
      const gross = 100.0;
      const discount = 0.0;
      // Customer returns a 20-value item and receives a 20-value
      // replacement instead of cash — total_returns still counts the
      // returned item's value (still real goods that came back).
      const returnedValue = 20.0;
      const replacementValue = 20.0; // equal to returnedValue

      final withEqualSwap = computeInvoiceNetTotal(
        grossSales: gross,
        discountAmount: discount,
        totalReturns: returnedValue,
        replacementItemsTotal: replacementValue,
      );

      final baselineNoReturnAtAll = computeInvoiceNetTotal(
        grossSales: gross,
        discountAmount: discount,
        totalReturns: 0,
        replacementItemsTotal: 0,
      );

      // The whole point of the feature: an equal-value in-kind swap must
      // be invisible to what the customer owes.
      expect(withEqualSwap, baselineNoReturnAtAll);
      expect(withEqualSwap, 100);
    });

    test('in-kind replacement with a DIFFERENT replacement value: reflects the '
        'exact surplus (pricier replacement) or shortfall (cheaper replacement)', () {
      const gross = 100.0;
      const discount = 0.0;
      const returnedValue = 20.0;

      // Surplus: replacement is worth MORE than what was returned — the
      // customer owes the difference on top.
      const pricierReplacement = 30.0;
      final surplusResult = computeInvoiceNetTotal(
        grossSales: gross,
        discountAmount: discount,
        totalReturns: returnedValue,
        replacementItemsTotal: pricierReplacement,
      );
      expect(surplusResult, 110); // 100 - 0 - 20 + 30
      expect(surplusResult - 100, pricierReplacement - returnedValue); // +10 surplus

      // Shortfall: replacement is worth LESS than what was returned — net
      // total drops below the no-return baseline by the difference.
      const cheaperReplacement = 12.0;
      final shortfallResult = computeInvoiceNetTotal(
        grossSales: gross,
        discountAmount: discount,
        totalReturns: returnedValue,
        replacementItemsTotal: cheaperReplacement,
      );
      expect(shortfallResult, 92); // 100 - 0 - 20 + 12
      expect(shortfallResult - 100, cheaperReplacement - returnedValue); // -8 shortfall
    });
  });

  group('InvoiceReturnItem', () {
    test('replacementSubtotal is null until both replacement fields are set (cash refund)', () {
      final cashReturn = InvoiceReturnItem(
        productId: 1,
        productName: 'لبن',
        quantity: 2,
        unitPrice: 10,
      );
      expect(cashReturn.refundMethod, 'cash');
      expect(cashReturn.replacementSubtotal, isNull);
      expect(cashReturn.subtotal, 20);
    });

    test('replacementSubtotal multiplies quantity × unit price once both are set', () {
      final inKindReturn = InvoiceReturnItem(
        productId: 1,
        productName: 'لبن',
        quantity: 2,
        unitPrice: 10,
        refundMethod: 'in_kind_replacement',
        replacementProductId: 5,
        replacementProductName: 'جبنة',
        replacementQuantity: 3,
        replacementUnitPrice: 4,
      );
      expect(inKindReturn.replacementSubtotal, 12);
    });
  });
}
