import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';

/// Guards the parity between what gets printed (bluetooth_printer.dart's
/// ESC/POS ticket) and what the on-screen preview shows
/// (invoice_preview_page.dart) — both render from buildReceiptPlan(), so
/// these assertions on the plan itself cover both consumers at once.
void main() {
  final full = InvoicePrintData(
    invoiceNumber: 'DINV-000123',
    clientName: 'أحمد محمد عبدالله',
    clientPhone: '01012345678',
    showPhone: true,
    delegateName: 'محمود الملواني',
    issuedAt: DateTime(2026, 7, 17, 14, 30),
    salesItems: const [
      PrintLineItem(
        productName: 'جبن سبريد طبيعي بالبسطرمة الفاخرة جداً',
        unit: 'علبة',
        quantity: 3,
        unitPrice: 45.5,
        subtotal: 136.5,
      ),
      PrintLineItem(productName: 'لبن', unit: 'لتر', quantity: 10, unitPrice: 20, subtotal: 200),
    ],
    returnedItems: const [
      PrintLineItem(productName: 'زبادي', unit: 'كيس', quantity: 2, unitPrice: 15, subtotal: 30),
    ],
    grossSales: 336.5,
    discountAmount: 10,
    totalReturns: 30,
    netTotal: 296.5,
    cashReceived: 200,
    balanceAddedToDebt: 96.5,
    customerBalanceAfter: 596.5,
    companyName: 'الخير للألبان',
    headerText: 'مرحباً بكم',
    footerText: 'شكراً لتعاملكم معنا',
    logoUrl:
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  final minimal = InvoicePrintData(
    invoiceNumber: 'DINV-000124',
    clientName: 'سارة علي',
    clientPhone: '01099999999',
    showPhone: false,
    delegateName: 'مندوب',
    issuedAt: DateTime(2026, 7, 17),
    salesItems: const [
      PrintLineItem(productName: 'لبن', unit: 'لتر', quantity: 1, unitPrice: 20, subtotal: 20),
    ],
    returnedItems: const [],
    grossSales: 20,
    discountAmount: 0,
    totalReturns: 0,
    netTotal: 20,
    cashReceived: 20,
    balanceAddedToDebt: 0,
    customerBalanceAfter: 0,
  );

  group('buildReceiptPlan — conditional lines present when applicable', () {
    late List<ReceiptElement> plan;
    late List<String> texts;

    setUp(() {
      plan = buildReceiptPlan(full);
      texts = plan.whereType<ReceiptTextLine>().map((e) => e.text).toList();
    });

    test('includes discount line when discountAmount > 0', () {
      expect(texts.any((t) => t.startsWith('الخصم: -10.00')), isTrue);
    });

    test('includes returns section + total when returnedItems is non-empty', () {
      expect(texts, contains('المرتجعات:'));
      expect(texts.any((t) => t.startsWith('المرتجعات: -30.00')), isTrue);
    });

    test('includes phone line when showPhone is true and phone is non-empty', () {
      expect(texts.any((t) => t.startsWith('الهاتف :')), isTrue);
    });

    test('includes exactly one logo element when logoUrl is set', () {
      expect(plan.whereType<ReceiptLogoElement>().length, 1);
    });

    test('المتبقي reflects balanceAddedToDebt when positive', () {
      expect(texts.singleWhere((t) => t.startsWith('المتبقي:')), contains('96.50'));
    });

    test('إجمالي المديونية reflects customerBalanceAfter', () {
      expect(texts.singleWhere((t) => t.startsWith('إجمالي المديونية:')), contains('596.50'));
    });

    test('long product name wraps onto continuation lines (12-char chunks)', () {
      // 'جبن سبريد طبيعي بالبسطرمة الفاخرة جداً' is 38 chars, so _wrapText(_, 12)
      // splits it into 4 chunks; the first is the row-formatted line (with
      // unit/qty/price/total columns appended), the rest are bare
      // continuation lines equal to their raw 12-char slice.
      expect(texts.any((t) => t.startsWith('جبن سبريد طب')), isTrue);
      expect(texts, contains('يعي بالبسطرم'));
      expect(texts, contains('ة الفاخرة جد'));
      expect(texts, contains('اً'));
    });

    test('field order matches the printed receipt structure', () {
      int indexOf(bool Function(String) f) => texts.indexWhere(f);
      final invoiceNoIdx = indexOf((t) => t.startsWith('رقم الفاتورة:'));
      final dateIdx = indexOf((t) => t.startsWith('التاريخ:'));
      final customerIdx = indexOf((t) => t.startsWith('العميل :'));
      final phoneIdx = indexOf((t) => t.startsWith('الهاتف :'));
      final delegateIdx = indexOf((t) => t.startsWith('المندوب:'));
      final grossIdx = indexOf((t) => t.startsWith('إجمالي المبيعات:'));
      final discountIdx = indexOf((t) => t.startsWith('الخصم:'));
      final returnsTotalIdx = indexOf((t) => t.startsWith('المرتجعات: -'));
      final debtIdx = indexOf((t) => t.startsWith('إجمالي المديونية:'));
      final netIdx = indexOf((t) => t.startsWith('الصافي المستحق:'));
      final paidIdx = indexOf((t) => t.startsWith('المدفوع:'));
      final remainingIdx = indexOf((t) => t.startsWith('المتبقي:'));
      final footerIdx = indexOf((t) => t == 'شكراً لتعاملكم معنا');

      expect(invoiceNoIdx, lessThan(dateIdx));
      expect(dateIdx, lessThan(customerIdx));
      expect(customerIdx, lessThan(phoneIdx));
      expect(phoneIdx, lessThan(delegateIdx));
      expect(grossIdx, lessThan(discountIdx));
      expect(discountIdx, lessThan(returnsTotalIdx));
      expect(returnsTotalIdx, lessThan(debtIdx));
      expect(debtIdx, lessThan(netIdx));
      expect(netIdx, lessThan(paidIdx));
      expect(paidIdx, lessThan(remainingIdx));
      expect(remainingIdx, lessThan(footerIdx));
    });
  });

  group('buildReceiptPlan — conditional lines omitted when not applicable', () {
    late List<String> texts;
    late List<ReceiptElement> plan;

    setUp(() {
      plan = buildReceiptPlan(minimal);
      texts = plan.whereType<ReceiptTextLine>().map((e) => e.text).toList();
    });

    test('omits phone line when showPhone is false', () {
      expect(texts.any((t) => t.startsWith('الهاتف :')), isFalse);
    });

    test('omits discount line when discountAmount is 0', () {
      expect(texts.any((t) => t.startsWith('الخصم:')), isFalse);
    });

    test('omits returns section entirely when returnedItems is empty', () {
      expect(texts.any((t) => t.startsWith('المرتجعات')), isFalse);
    });

    test('omits logo element when logoUrl is null', () {
      expect(plan.whereType<ReceiptLogoElement>(), isEmpty);
    });

    test('omits header/footer lines when unset', () {
      expect(texts.contains('مرحباً بكم'), isFalse);
      // Company name line is also absent since companyName defaults to ''.
      expect(texts.any((t) => t == full.companyName), isFalse);
    });

    test('المتبقي is 0.00 when balanceAddedToDebt is 0', () {
      expect(texts.singleWhere((t) => t.startsWith('المتبقي:')), contains('0.00'));
    });
  });
}
