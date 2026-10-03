import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:alkhair_mobileapp/core/utils/bluetooth_printer.dart';

/// Regression coverage for the "app freezes then crashes on طباعة الفاتورة"
/// bug. Root cause: print_bluetooth_thermal 1.2.2's Android `writebytes`
/// handler runs on the Android main thread and grows its ByteArray one byte
/// at a time (O(n²) copying) before a blocking socket write; the whole
/// receipt used to go through ONE such call (124KB for a typical 3-item
/// 80mm receipt => ~8 GB copied on the main thread => ANR). The ticket is
/// now a list of small, self-contained ESC/POS commands, one writeBytes
/// call each, and the bitmap thresholding/encoding runs off the UI isolate.

TextStyle _offlineStyle({required double size, required bool bold}) => TextStyle(
      fontSize: size,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: Colors.black,
      height: 1.25,
    );

/// Same shape as the real uploaded logo: a 300x300 transparent PNG data URI
/// with a dark mark in the middle.
String _logo300() {
  final logo = img.Image(width: 300, height: 300, numChannels: 4);
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 300; x++) {
      final inMark = (x - 150).abs() < 100 && (y - 150).abs() < 100;
      logo.setPixelRgba(x, y, 0, 0, 0, inMark ? 255 : 0);
    }
  }
  return 'data:image/png;base64,${base64Encode(img.encodePng(logo))}';
}

/// Every conditional receipt line present: logo, header/footer, region,
/// discount, returns with an in-kind replacement, prior debt, QR. 13 items
/// = the largest real delegate invoice in production, with the longest
/// real product names.
InvoicePrintData _realisticReceipt({String paper = '80mm', int items = 13}) => InvoicePrintData(
      invoiceNumber: 'DINV-004512',
      clientName: 'سوبر ماركت الهدى والنور',
      clientPhone: '01000000000',
      clientRegion: 'المنطقة الصناعية الثالثة',
      delegateName: 'أحمد محمود عبد الرحمن',
      issuedAt: DateTime(2026, 10, 3, 9, 0),
      salesItems: [
        for (var i = 0; i < items; i++)
          const PrintLineItem(
              productName: 'جبن سبريد طبيعي بالشيدر 2.4 ك',
              unit: 'كرتونة',
              quantity: 12.5,
              unitPrice: 265.75,
              subtotal: 3321.88),
      ],
      returnedItems: const [
        PrintLineItem(
            productName: 'ملح خفيف طبيعي - جردل/سيرفيس',
            unit: 'جردل',
            quantity: 2,
            unitPrice: 90,
            subtotal: 180,
            refundMethod: 'in_kind_replacement',
            replacementProductName: 'لبن جاموسي',
            replacementUnit: 'لتر',
            replacementQuantity: 6,
            replacementUnitPrice: 30,
            replacementSubtotal: 180),
        PrintLineItem(productName: 'زبادي', unit: 'كيس', quantity: 1, unitPrice: 10, subtotal: 10),
      ],
      grossSales: 43184.44,
      discountAmount: 150,
      totalReturns: 190,
      replacementItemsTotal: 180,
      netTotal: 43024.44,
      cashReceived: 40000,
      balanceAddedToDebt: 3024.44,
      priorDebt: 1200,
      companyName: 'الخير للألبان',
      headerText: 'أهلاً بكم في الخير للألبان',
      footerText: 'شكراً لتعاملكم معنا',
      logoUrl: _logo300(),
      paperWidthDots: rasterWidthDotsForPaper(paper),
    );

/// Rows covered by one "GS v 0" command (header: 1D 76 30 00 xL xH yL yH).
int _bandRows(Uint8List cmd) {
  expect(cmd.sublist(0, 4), [0x1D, 0x76, 0x30, 0x00], reason: 'every middle chunk is one raster command');
  return cmd[6] | (cmd[7] << 8);
}

void main() {
  for (final paper in ['58mm', '80mm']) {
    testWidgets('$paper realistic receipt: size, timing, and every write is a small self-contained command',
        (tester) async {
      final svc = BluetoothPrinterService();
      final d = _realisticReceipt(paper: paper);

      final renderClock = Stopwatch()..start();
      final image = (await tester.runAsync(
          () => svc.renderReceiptImageForTest(d, styleBuilder: _offlineStyle)))!;
      renderClock.stop();
      final buildClock = Stopwatch()..start();
      final ticket = (await tester.runAsync(
          () => svc.buildTicketForTest(d, styleBuilder: _offlineStyle)))!;
      buildClock.stop();

      final total = ticket.fold<int>(0, (a, c) => a + c.length);
      final largest = ticket.map((c) => c.length).reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print('[$paper, 13 items + returns + logo + QR] bitmap ${image.width}x${image.height} '
          '(${(image.width * image.height * 4 / 1048576).toStringAsFixed(1)}MB RGBA), '
          'render ${renderClock.elapsedMilliseconds}ms, full ticket ${buildClock.elapsedMilliseconds}ms, '
          'ticket ${(total / 1024).toStringAsFixed(1)}KB in ${ticket.length} writes, largest ${largest}B '
          '(before: one ${(total / 1024).toStringAsFixed(1)}KB write = '
          '${(total * total / 2 / 1e9).toStringAsFixed(1)}GB of plugin main-thread copying; '
          'now ${(largest * largest / 2 / 1e6).toStringAsFixed(1)}M per write)');

      final widthBytes = (image.width + 7) ~/ 8;
      // Each write stays tiny, so the plugin's O(n²) per-call loop is cheap.
      expect(largest, lessThanOrEqualTo(8 + widthBytes * kRasterBandRows));
      expect(largest, lessThan(2048));

      // Preamble: reset + line spacing 0 (so the plugin's per-call "\n"
      // between bands feeds nothing). Trailer: restore spacing, feed, cut.
      expect(ticket.first, [0x1B, 0x40, 0x1B, 0x33, 0x00]);
      expect(ticket.last, [0x1B, 0x32, 0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x03]);

      final bands = ticket.sublist(1, ticket.length - 1);
      var rows = 0;
      for (final band in bands) {
        final h = _bandRows(band);
        expect(band[4] | (band[5] << 8), widthBytes);
        expect(band.length, 8 + widthBytes * h);
        rows += h;
      }
      expect(rows, image.height, reason: 'bands cover the whole bitmap, no rows lost or duplicated');

      // Runaway-growth guard only. The test font's square glyphs wrap far
      // more than Cairo: with the real Cairo font this same receipt is
      // 3242 rows at 58mm / 2775 at 80mm.
      expect(image.height, lessThan(8000));
    });
  }

  testWidgets('raster bits match the alpha-composited threshold pixel-for-pixel', (tester) async {
    final svc = BluetoothPrinterService();
    final d = _realisticReceipt(items: 3);
    final image = (await tester.runAsync(() => svc.renderReceiptImageForTest(d, styleBuilder: _offlineStyle)))!;
    final ticket = (await tester.runAsync(() => svc.buildTicketForTest(d, styleBuilder: _offlineStyle)))!;
    final widthBytes = (image.width + 7) ~/ 8;

    var y = 0;
    var black = 0;
    for (final band in ticket.sublist(1, ticket.length - 1)) {
      final h = _bandRows(band);
      for (var r = 0; r < h; r++, y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final alpha = p.a / p.maxChannelValue;
          final expected = p.luminance * alpha + p.maxChannelValue * (1 - alpha) < 160;
          final bit = band[8 + r * widthBytes + (x >> 3)] & (0x80 >> (x & 7)) != 0;
          if (bit != expected) fail('pixel ($x,$y): bit=$bit expected=$expected');
          if (bit) black++;
        }
      }
    }
    expect(black, greaterThan(0));
  });

  testWidgets('logo is centered at its native 300px, not stretched to the 576-dot paper width',
      (tester) async {
    final image = (await tester.runAsync(() => BluetoothPrinterService()
        .renderReceiptImageForTest(_realisticReceipt(items: 1), styleBuilder: _offlineStyle)))!;
    // The logo's 200px dark mark sits at x 50..249 within the 300px logo,
    // so centered on 576 dots it must span ~188..387 on the first logo rows.
    const row = 10 + 150; // render's top padding + middle of the logo
    final dark = [
      for (var x = 0; x < image.width; x++)
        if (image.getPixel(x, row).luminance < 100) x
    ];
    expect(dark, isNotEmpty);
    expect(dark.first, inInclusiveRange(185, 192));
    expect(dark.last, inInclusiveRange(383, 390));
  });

  group('printInvoice over the plugin channel', () {
    const channel = MethodChannel('groons.web.app/print');
    late List<Object?> writes;
    late bool Function(int callIndex) writeSucceeds;

    setUp(() {
      writes = [];
      writeSucceeds = (_) => true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'writebytes') {
          writes.add(call.arguments);
          return writeSucceeds(writes.length - 1);
        }
        if (call.method == 'connectionstatus') return true;
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    InvoicePrintData small() => InvoicePrintData(
          invoiceNumber: 'D1',
          clientName: 'عميل',
          clientPhone: '',
          delegateName: 'مندوب',
          issuedAt: DateTime(2026, 10, 3),
          salesItems: const [PrintLineItem(productName: 'جبن', quantity: 1, unitPrice: 10, subtotal: 10)],
          returnedItems: const [],
          grossSales: 10,
          totalReturns: 0,
          netTotal: 10,
          cashReceived: 10,
          balanceAddedToDebt: 0,
          paperWidthDots: 576,
        );

    testWidgets('sends many small awaited writes as plain lists, reporting progress to 100%', (tester) async {
      final progress = <(PrintStage, double)>[];
      final outcome = await tester.runAsync(() => BluetoothPrinterService(debugStyleBuilder: _offlineStyle)
          .printInvoice(small(), onProgress: (s, p) => progress.add((s, p))));

      expect(outcome, PrintOutcome.success);
      expect(writes.length, greaterThan(3));
      for (final w in writes) {
        // A Uint8List would reach Android as byte[] and break the plugin's
        // `as List<Int>` cast.
        expect(w, isNot(isA<Uint8List>()));
        expect((w as List).length, lessThan(2048));
      }
      expect(progress.first.$1, PrintStage.preparing);
      expect(progress.last, (PrintStage.sending, 1.0));
    });

    testWidgets('a link dropping mid-receipt is reported as interrupted and NOT blindly resent', (tester) async {
      writeSucceeds = (i) => i < 3;
      final outcome = await tester.runAsync(() => BluetoothPrinterService(debugStyleBuilder: _offlineStyle).printInvoice(small()));
      expect(outcome, PrintOutcome.interrupted);
      expect(writes.length, 4);
    });

    testWidgets('nothing written and no device to reconnect to => sendFailed, never a throw', (tester) async {
      writeSucceeds = (_) => false;
      final outcome = await tester.runAsync(() => BluetoothPrinterService(debugStyleBuilder: _offlineStyle).printInvoice(small()));
      expect(outcome, PrintOutcome.sendFailed);
      expect(writes.length, 1);
    });
  });
}
