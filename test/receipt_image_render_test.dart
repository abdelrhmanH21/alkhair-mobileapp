import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';

/// Exercises the real bitmap-rendering pipeline behind the fix for garbled
/// Arabic on physical thermal prints (see bluetooth_printer.dart's
/// _renderReceiptImage doc comment) — Canvas/TextPainter/PictureRecorder
/// only work under a live Flutter binding, so this has to be a
/// flutter_test, not a plain unit test.
///
/// A plain [_offlineStyle] is injected via renderReceiptImageForTest's
/// styleBuilder seam instead of the real Cairo font: this sandbox/CI has no
/// outbound network access, and google_fonts' real font fetch either hangs
/// (waiting on a connection that never resolves) or reports its expected
/// failure as an uncaught test error — neither of which this test needs to
/// fight, since none of its assertions (image size, non-blank output)
/// depend on the actual Cairo glyphs. Production code always uses the real
/// Cairo builder (styleBuilder is left null outside tests).
TextStyle _offlineStyle({required double size, required bool bold}) => TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: Colors.black,
      height: 1.25,
    );

void main() {
  testWidgets('renders a real, non-blank RGBA image sized to the printer raster width',
      (tester) async {
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000300',
      clientName: 'محمد سعيد',
      clientPhone: '01055566677',
      delegateName: 'مندوب تجريبي',
      issuedAt: DateTime(2026, 7, 17, 9, 0),
      salesItems: const [
        PrintLineItem(productName: 'لبن جاموسي كامل الدسم', unit: 'لتر', quantity: 2, unitPrice: 20, subtotal: 40),
        PrintLineItem(productName: 'جبن', unit: 'كيلو', quantity: 1, unitPrice: 60, subtotal: 60),
      ],
      returnedItems: const [
        PrintLineItem(productName: 'زبادي', unit: 'كيس', quantity: 1, unitPrice: 10, subtotal: 10),
      ],
      grossSales: 100,
      discountAmount: 5,
      totalReturns: 10,
      netTotal: 85,
      cashReceived: 50,
      balanceAddedToDebt: 35,
      customerBalanceAfter: 120,
      companyName: 'الخير للألبان',
      headerText: 'أهلاً بكم',
      footerText: 'شكراً لتعاملكم معنا',
    );

    // _renderReceiptImage's Canvas/PictureRecorder/Picture.toImage work is
    // driven by real engine callbacks, not the fake async clock testWidgets
    // normally runs under — without runAsync() those callbacks never fire
    // and the await below hangs forever.
    final image = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(data, styleBuilder: _offlineStyle));

    expect(image, isNotNull);
    expect(image!.width, 384);
    expect(image.height, greaterThan(200));

    // Sanity check that real content was painted, not just a blank white
    // canvas — at least one pixel must be dark (text/line ink).
    var sawDarkPixel = false;
    for (var y = 0; y < image.height && !sawDarkPixel; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).luminance < 100) {
          sawDarkPixel = true;
          break;
        }
      }
    }
    expect(sawDarkPixel, isTrue, reason: 'expected at least some rendered (dark) content');
  });

  testWidgets('handles an invoice with no returns and no header/footer text', (tester) async {
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000301',
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

    final image = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(data, styleBuilder: _offlineStyle));
    expect(image, isNotNull);
    expect(image!.width, 384);
    expect(image.height, greaterThan(50));
  });
}
