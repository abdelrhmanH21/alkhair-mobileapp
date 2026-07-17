import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/invoice_preview_page.dart';

/// Pumps ReceiptPreviewCard for real and checks its rendered widget tree
/// against buildReceiptPlan(data) — the same plan the real ESC/POS ticket is
/// built from — so this exercises the actual widget tree, not just the plan
/// data structure in isolation.
///
/// The items table is the one deliberate exception: buildReceiptPlan() bakes
/// item rows into fixed-width padded strings for the printer's monospace
/// columns, so the polished preview renders those rows from
/// data.salesItems/returnedItems directly instead (see invoice_preview_page.dart's
/// doc comment) — this file checks the individual field VALUES render
/// cleanly (unpadded) rather than the old padded-string lines.
void main() {
  /// The item-table portion of a plan — from the "الصنف" header marker up
  /// to (not including) "إجمالي المبيعات:" — is rendered by ReceiptPreviewCard's
  /// own _ItemsSection/_ItemsTable, not as literal ReceiptTextLine text.
  /// Every other line must still appear verbatim.
  List<String> nonItemTableTextLines(List<ReceiptElement> plan) {
    final result = <String>[];
    var inItemsSection = false;
    for (final el in plan) {
      if (el is ReceiptTextLine && el.text.trimLeft().startsWith('الصنف')) {
        inItemsSection = true;
        continue;
      }
      if (inItemsSection) {
        if (el is ReceiptTextLine && el.text.startsWith('إجمالي المبيعات:')) {
          inItemsSection = false;
        } else {
          continue;
        }
      }
      if (el is ReceiptTextLine) result.add(el.text);
    }
    return result;
  }

  testWidgets('renders every non-item-table plan line verbatim, in a real Divider-separated card',
      (tester) async {
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000200',
      clientName: 'محمد سعيد',
      clientPhone: '01055566677',
      showPhone: true,
      delegateName: 'مندوب تجريبي',
      issuedAt: DateTime(2026, 7, 17, 9, 0),
      salesItems: const [
        PrintLineItem(productName: 'لبن', unit: 'لتر', quantity: 2, unitPrice: 20, subtotal: 40),
      ],
      returnedItems: const [],
      grossSales: 40,
      discountAmount: 5,
      totalReturns: 0,
      netTotal: 35,
      cashReceived: 35,
      balanceAddedToDebt: 0,
      customerBalanceAfter: 0,
      companyName: 'الخير للألبان',
      // No logoUrl — keeps this test free of network/image decoding.
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptPreviewCard(data: data)))));
    await tester.pumpAndSettle();

    final plan = buildReceiptPlan(data);

    for (final expected in nonItemTableTextLines(plan)) {
      expect(find.text(expected), findsOneWidget, reason: 'missing rendered line: "$expected"');
    }

    // Dash-separator lines are gone — replaced with real Divider widgets.
    expect(find.text('-' * 42), findsNothing);
    expect(find.byType(Divider), findsWidgets);

    // No BluetoothInfo/device-picker/connect affordance anywhere on this
    // page — the whole point is it works without a printer.
    expect(find.textContaining('طابعة'), findsNothing);

    // Uses the app's Cairo font, not the old monospace style.
    final headerCell = tester.widget<Text>(find.text('الصنف'));
    expect(headerCell.style?.fontFamily, isNot('monospace'));
  });

  testWidgets('items table: clean unpadded per-field cells with column headers', (tester) async {
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000201',
      clientName: 'عميل',
      clientPhone: '',
      delegateName: 'مندوب',
      issuedAt: DateTime(2026, 7, 17),
      salesItems: const [
        PrintLineItem(productName: 'زبادي', unit: 'كيس', quantity: 3, unitPrice: 12.5, subtotal: 37.5),
      ],
      returnedItems: const [],
      grossSales: 37.5,
      totalReturns: 0,
      netTotal: 37.5,
      cashReceived: 37.5,
      balanceAddedToDebt: 0,
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptPreviewCard(data: data)))));
    await tester.pumpAndSettle();

    // Column headers, matching the reference layout order.
    for (final header in ['الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي']) {
      expect(find.text(header), findsOneWidget);
    }

    // Item fields render as their own clean, unpadded values — not baked
    // into one fixed-width printer-column string.
    expect(find.text('زبادي'), findsOneWidget);
    expect(find.text('كيس'), findsOneWidget);
    expect(find.text('3.00'), findsOneWidget);
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('37.50'), findsOneWidget);

    // The whole table is a real Flutter Table, not text lines of dashes.
    expect(find.byType(Table), findsNWidgets(2)); // header table + body table
  });

  testWidgets('returns section renders its own labeled table only when returnedItems is non-empty',
      (tester) async {
    final withReturns = InvoicePrintData(
      invoiceNumber: 'DINV-000202',
      clientName: 'عميل',
      clientPhone: '',
      delegateName: 'مندوب',
      issuedAt: DateTime(2026, 7, 17),
      salesItems: const [
        PrintLineItem(productName: 'لبن', unit: 'لتر', quantity: 1, unitPrice: 20, subtotal: 20),
      ],
      returnedItems: const [
        PrintLineItem(productName: 'جبن', unit: 'علبة', quantity: 2, unitPrice: 15, subtotal: 30),
      ],
      grossSales: 20,
      totalReturns: 30,
      netTotal: -10,
      cashReceived: 0,
      balanceAddedToDebt: 0,
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptPreviewCard(data: withReturns)))));
    await tester.pumpAndSettle();

    expect(find.text('المرتجعات'), findsOneWidget);
    expect(find.text('جبن'), findsOneWidget);
    // Returned quantity is shown with the same '-' prefix buildReceiptPlan()
    // uses for the printer's returns rows.
    expect(find.text('-2.00'), findsOneWidget);

    final withoutReturns = InvoicePrintData(
      invoiceNumber: 'DINV-000203',
      clientName: 'عميل',
      clientPhone: '',
      delegateName: 'مندوب',
      issuedAt: DateTime(2026, 7, 17),
      salesItems: const [
        PrintLineItem(productName: 'لبن', unit: 'لتر', quantity: 1, unitPrice: 20, subtotal: 20),
      ],
      returnedItems: const [],
      grossSales: 20,
      totalReturns: 0,
      netTotal: 20,
      cashReceived: 20,
      balanceAddedToDebt: 0,
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptPreviewCard(data: withoutReturns)))));
    await tester.pumpAndSettle();

    expect(find.text('المرتجعات'), findsNothing);
  });

  testWidgets('long product names wrap cleanly within their own column, not mid-word across totals',
      (tester) async {
    const longName = 'جبن سبريد طبيعي بالبسطرمة الفاخرة جداً';
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000204',
      clientName: 'عميل',
      clientPhone: '',
      delegateName: 'مندوب',
      issuedAt: DateTime(2026, 7, 17),
      salesItems: const [
        PrintLineItem(productName: longName, unit: 'علبة', quantity: 1, unitPrice: 50, subtotal: 50),
      ],
      returnedItems: const [],
      grossSales: 50,
      totalReturns: 0,
      netTotal: 50,
      cashReceived: 50,
      balanceAddedToDebt: 0,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptPreviewCard(data: data)))),
    );
    await tester.pumpAndSettle();

    // The full name renders as ONE Text widget (Flutter's own soft-wrap
    // inside the flexible name column), unlike buildReceiptPlan()'s printer
    // path which — unchanged — still splits it into 12-char chunks
    // ('جبن سبريد طب', 'يعي بالبسطرم', ...) for the physical ticket.
    expect(find.text(longName), findsOneWidget);
    expect(find.text('جبن سبريد طب'), findsNothing);
  });
}
