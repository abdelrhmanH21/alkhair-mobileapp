import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/settlement_page.dart';

void main() {
  group('parseSettlementAmounts', () {
    test('wallet-only collection: blank cash field is treated as 0, not rejected', () {
      final result = parseSettlementAmounts('', '150.50');
      expect(result.cash, 0.0);
      expect(result.wallet, 150.50);
    });

    test('cash-only collection: blank wallet field is treated as 0, not rejected', () {
      final result = parseSettlementAmounts('200', '');
      expect(result.cash, 200.0);
      expect(result.wallet, 0.0);
    });

    test('both fields provided', () {
      final result = parseSettlementAmounts('100', '50');
      expect(result.cash, 100.0);
      expect(result.wallet, 50.0);
    });

    test('whitespace-only fields are treated the same as empty', () {
      final result = parseSettlementAmounts('  ', '75');
      expect(result.cash, 0.0);
      expect(result.wallet, 75.0);
    });

    test('rejects when both fields are blank — nothing to submit', () {
      expect(() => parseSettlementAmounts('', ''), throwsFormatException);
    });

    test('rejects when both resolve to zero', () {
      expect(() => parseSettlementAmounts('0', '0'), throwsFormatException);
    });

    test('rejects genuinely non-numeric cash input', () {
      expect(() => parseSettlementAmounts('abc', '50'), throwsFormatException);
    });

    test('rejects genuinely non-numeric wallet input', () {
      expect(() => parseSettlementAmounts('50', 'xyz'), throwsFormatException);
    });

    test('rejects a negative amount', () {
      expect(() => parseSettlementAmounts('-10', '50'), throwsFormatException);
    });
  });
}
