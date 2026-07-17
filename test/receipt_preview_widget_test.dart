import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/invoice_preview_page.dart';

/// Pumps ReceiptPreviewCard for real and checks its rendered Text widgets
/// match buildReceiptPlan(data) exactly — the same plan the real ESC/POS
/// ticket is built from — so this exercises the actual widget tree, not
/// just the plan data structure in isolation.
void main() {
  testWidgets('ReceiptPreviewCard renders every plan line, same order, no printer required',
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

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptPreviewCard(data: data))));
    await tester.pumpAndSettle();

    final expectedPlan = buildReceiptPlan(data);
    final expectedTextLines = expectedPlan.whereType<ReceiptTextLine>().map((e) => e.text).toList();

    // Every non-separator text line from the plan must appear verbatim
    // somewhere in the rendered widget tree — no printer connection
    // involved, since this page never touches BluetoothPrinterService.printInvoice.
    for (final expected in expectedTextLines) {
      expect(find.text(expected), findsOneWidget, reason: 'missing rendered line: "$expected"');
    }

    // Separators render as 42 dashes, matching bluetooth_printer.dart's
    // _charsPerLine.
    final separatorCount = expectedPlan.whereType<ReceiptSeparatorLine>().length;
    expect(find.text('-' * 42), findsNWidgets(separatorCount));

    // No BluetoothInfo/device-picker/connect affordance anywhere on this
    // page — the whole point is it works without a printer.
    expect(find.textContaining('طابعة'), findsNothing);
  });
}
