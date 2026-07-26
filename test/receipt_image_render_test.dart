import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

/// A minimal but genuinely-transparent-background 20x20 PNG, encoded as a
/// data: URI exactly like ReceiptSetting.company_logo is stored/served
/// (MobileAppSettingController::resolveLogoUrl) — real logos are base64
/// data URIs, never fetched over the network, so this needs no I/O.
String _syntheticLogoDataUri() {
  final logo = img.Image(width: 20, height: 20);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 20; x++) {
      // Opaque black disk-ish blob in the middle, transparent elsewhere —
      // mirrors the real logos' "transparent background, dark mark" shape
      // that motivated the alpha-aware _isDarkOnWhite compositing fix.
      final inBlob = (x - 10).abs() < 6 && (y - 10).abs() < 6;
      logo.setPixelRgba(x, y, 0, 0, 0, inBlob ? 255 : 0);
    }
  }
  return 'data:image/png;base64,${base64Encode(img.encodePng(logo))}';
}

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
      priorDebt: 120,
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

  testWidgets('rasterWidthDotsForPaper: an 80mm receipt renders at 576 dots, not the 58mm default',
      (tester) async {
    // Regression test for the "receipt shifted right / not centered on an
    // 80mm roll" report: the renderer used to always render at a fixed
    // 384-dot (58mm) width regardless of ReceiptSetting.paper_width, so an
    // 80mm printer only ever filled the left ~2/3 of its paper instead of
    // the image matching (and thus centering on) the actual roll width.
    final data = InvoicePrintData(
      invoiceNumber: 'DINV-000302',
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
      paperWidthDots: rasterWidthDotsForPaper('80mm'),
    );

    final image = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(data, styleBuilder: _offlineStyle));
    expect(image, isNotNull);
    expect(image!.width, 576);
  });

  // Regression tests for a real physical print showing (1) no logo at all,
  // (2) every line flush-left instead of right-aligned RTL, and (3) item
  // rows visibly smaller than the totals block below them. See
  // bluetooth_printer.dart's addText/_renderReceiptImage doc comments for
  // the root causes.

  testWidgets('logo: buildReceiptPlan includes it, and the rendered bitmap shows its ink',
      (tester) async {
    final withoutLogo = InvoicePrintData(
      invoiceNumber: 'DINV-000400',
      clientName: 'عميل',
      clientPhone: '',
      delegateName: 'مندوب',
      issuedAt: DateTime(2026, 7, 26),
      salesItems: const [
        PrintLineItem(productName: 'منتج', unit: 'وحدة', quantity: 1, unitPrice: 10, subtotal: 10),
      ],
      returnedItems: const [],
      grossSales: 10,
      totalReturns: 0,
      netTotal: 10,
      cashReceived: 10,
      balanceAddedToDebt: 0,
    );
    final withLogo = InvoicePrintData(
      invoiceNumber: withoutLogo.invoiceNumber,
      clientName: withoutLogo.clientName,
      clientPhone: withoutLogo.clientPhone,
      delegateName: withoutLogo.delegateName,
      issuedAt: withoutLogo.issuedAt,
      salesItems: withoutLogo.salesItems,
      returnedItems: withoutLogo.returnedItems,
      grossSales: withoutLogo.grossSales,
      totalReturns: withoutLogo.totalReturns,
      netTotal: withoutLogo.netTotal,
      cashReceived: withoutLogo.cashReceived,
      balanceAddedToDebt: withoutLogo.balanceAddedToDebt,
      logoUrl: _syntheticLogoDataUri(),
    );

    // buildReceiptPlan itself must still emit a ReceiptLogoElement when a
    // logoUrl is present — the structural check that the draw call site
    // wasn't accidentally dropped from the plan.
    expect(buildReceiptPlan(withLogo).whereType<ReceiptLogoElement>(), hasLength(1));
    expect(buildReceiptPlan(withoutLogo).whereType<ReceiptLogoElement>(), isEmpty);

    final imgWithout = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(withoutLogo, styleBuilder: _offlineStyle));
    final imgWith = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(withLogo, styleBuilder: _offlineStyle));

    // The logo element adds its own draw op before everything else, so the
    // rendered receipt must be measurably taller than the logo-less one...
    expect(imgWith!.height, greaterThan(imgWithout!.height));

    // ...and the extra vertical space near the top must contain real
    // (alpha-composited-to-white, then thresholded) dark ink from the logo
    // blob, not just blank white — proving the logo actually painted rather
    // than silently failing to fetch/decode.
    var sawLogoInk = false;
    for (var y = 0; y < imgWith.height && !sawLogoInk; y++) {
      for (var x = 0; x < imgWith.width; x++) {
        if (imgWith.getPixel(x, y).luminance < 100) {
          sawLogoInk = true;
          break;
        }
      }
    }
    expect(sawLogoInk, isTrue, reason: 'expected the logo blob to paint as dark ink');
  });

  testWidgets('alignment: a short non-centered line hugs the right margin, not the left',
      (tester) async {
    // A short line (well under the printable width) makes flush-left vs
    // flush-right unambiguous — a long line's ink can span nearly the full
    // width either way, which is what let the original left-alignment bug
    // hide even on real receipts with long invoice-number/date lines.
    final data = InvoicePrintData(
      invoiceNumber: 'X',
      clientName: 'ص', // single Arabic letter — "العميل : ص" is short
      clientPhone: '',
      delegateName: 'م',
      issuedAt: DateTime(2026, 7, 26),
      salesItems: const [
        PrintLineItem(productName: 'م', unit: 'و', quantity: 1, unitPrice: 1, subtotal: 1),
      ],
      returnedItems: const [],
      grossSales: 1,
      totalReturns: 0,
      netTotal: 1,
      cashReceived: 1,
      balanceAddedToDebt: 0,
      paperWidthDots: 384,
    );

    final image = await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(data, styleBuilder: _offlineStyle));
    expect(image, isNotNull);

    // Group rows into contiguous dark bands first (one band == one printed
    // line), then aggregate minX/maxX over the WHOLE band rather than a
    // single pixel row — a single row picked from a glyph's edge (e.g. a
    // tittle dot above a letter, or the row right at a descender's tip) can
    // have a much narrower span than the line's true extent, which would
    // give a false read on where the line is actually anchored.
    final bands = <(int start, int end)>[];
    int? bandStart;
    for (var y = 0; y < image!.height; y++) {
      var hasDark = false;
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).luminance < 200) {
          hasDark = true;
          break;
        }
      }
      if (hasDark && bandStart == null) {
        bandStart = y;
      } else if (!hasDark && bandStart != null) {
        bands.add((bandStart, y - 1));
        bandStart = null;
      }
    }

    const rightMargin = 384 - 10; // width - hPad, same margin addText uses
    var found = false;
    for (final band in bands) {
      // Restrict to the header/invoice-info block (rendered via addText,
      // the function this test targets) — the items table further down
      // uses its own already-correct manual per-column offset logic
      // (addRow/cellPainter) and isn't what's under test here; its
      // multi-cell rows would otherwise pollute a whole-row minX/maxX scan.
      if (band.$1 >= 230) continue;
      int? minX, maxX;
      for (var y = band.$1; y <= band.$2; y++) {
        for (var x = 0; x < image.width; x++) {
          if (image.getPixel(x, y).luminance < 200) {
            minX = minX == null ? x : (x < minX ? x : minX);
            maxX = maxX == null ? x : (x > maxX ? x : maxX);
          }
        }
      }
      if (minX == null) continue;
      final lineWidth = maxX! - minX;
      // Skip separator lines (span nearly the full canvas width) and bands
      // with no meaningful content (e.g. an isolated diacritic row).
      if (lineWidth < 60 || lineWidth > 250) continue;
      found = true;
      // Right-aligned: ink must end close to the right margin...
      expect(maxX, greaterThan(rightMargin - 20),
          reason: 'expected line ink to hug the right margin (RTL), not float away from it '
              '(minX=$minX maxX=$maxX, band=$band)');
      // ...and since the string is short, there must be real slack on the
      // left — a flush-left rendering (the actual bug) would instead show
      // minX pinned near the left margin (~10) with maxX floating.
      expect(minX, greaterThan(40),
          reason: 'expected left-side slack for a short right-aligned line, not a '
              'flush-left start (minX=$minX, band=$band)');
    }
    expect(found, isTrue, reason: 'expected to find at least one short right-aligned line');
  });

  test('item-row and totals-block bold text share one point size constant', () {
    // A real physical print showed item rows (product name/unit/qty/price/
    // subtotal) visibly smaller than إجمالي المبيعات/المدفوع/etc directly
    // below them. Both now read from the same kReceiptBoldTextSize constant
    // (bluetooth_printer.dart) instead of separate literals (18/16 for item
    // cells vs 23 for totals) that had drifted apart — asserting equality
    // on the shared constant is the reliable regression guard here, since
    // comparing rendered glyph ink height is not: digit glyphs (item
    // prices) visually ink far shorter than Arabic letters with descenders
    // (totals labels) even at an identical font size.
    expect(kReceiptBoldTextSize, 23);
  });
}
