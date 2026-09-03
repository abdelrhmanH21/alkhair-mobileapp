import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
// intl's own TextDirection (LTR/RTL, used for locale directionality) would
// otherwise collide with dart:ui's TextDirection (rtl/ltr) that Canvas text
// painting below needs — only DateFormat is used from this import.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'date_parsing.dart';

// Default/fallback raster width (58mm paper) — used only when a receipt's
// actual configured paper width (InvoicePrintData.paperWidthDots, sourced
// from ReceiptSetting.paper_width) isn't available, e.g. the standalone
// logo preview in invoice_preview_page.dart which isn't tied to a specific
// receipt render.
const int _logoWidthDots = 384;

/// Printer raster width in dots for a given `ReceiptSetting.paper_width`
/// value ('58mm'/'80mm'). Standard ESC/POS thermal printers at 203dpi print
/// 384 dots on 58mm paper (~48mm printable) and 576 dots on 80mm paper
/// (~72mm printable) — rendering the receipt at a width that doesn't match
/// the physical paper leaves it flush to one side of the roll instead of
/// filling/centering it, which is what "receipt shifted right and not
/// centered" in a real 80mm print turned out to be: the image was always
/// rendered at the 58mm-equivalent 384-dot width regardless of the admin's
/// configured paper size.
int rasterWidthDotsForPaper(String paperWidth) => paperWidth == '80mm' ? 576 : 384;

/// Point size shared by the totals-block bold lines (إجمالي المبيعات،
/// المدفوع، etc — see the `bold` branch of _renderReceiptImage's per-line
/// size switch) and the items/returns table's row cells (name/unit/qty/
/// price/subtotal — see addItemsTable's cellPainter calls). A real physical
/// print showed the item rows noticeably smaller than the totals directly
/// below them; kept as one shared constant (rather than two matching
/// literals) so they can never drift apart again, and so a test can assert
/// on this value directly instead of measuring rendered glyph ink (fragile —
/// digit glyphs vs Arabic letters with descenders visually ink far less
/// than their nominal font size would suggest).
@visibleForTesting
const double kReceiptBoldTextSize = 23;

// SAME fixed URL on every single invoice, everywhere (web + mobile print) —
// no query params, no per-invoice variation — so every scan, from any
// invoice, lands on the exact same public feedback form.
const String kFeedbackUrl = 'https://feedback.alkhairdairies.com/complain';
// QR raster size in dots — fixed regardless of paper width (58mm/80mm both
// have plenty of room at this size) so the QR itself is byte-for-byte
// identical across every receipt, not just its encoded URL.
const double _qrSizeDots = 160;
// Luminance below this prints as a black dot — shared by the real ESC/POS
// rasterizer and the on-screen preview's logo rendering so both show the
// exact same monochrome conversion.
const int _blackThreshold = 160;

enum ReceiptAlign { left, center, right }

/// Why a [BluetoothPrinterService.connect] attempt failed, specific enough
/// for the UI to show an actionable Arabic message instead of one generic
/// "فشل الاتصال بالطابعة" regardless of cause.
enum PrinterConnectError {
  /// BLUETOOTH_CONNECT/BLUETOOTH_SCAN runtime permission not granted. On
  /// Android 12+ this is the most likely root cause of "connection
  /// failures" — declaring the permissions in the manifest is not enough,
  /// they must be requested at runtime, and the native
  /// print_bluetooth_thermal plugin silently no-ops (never resolves the
  /// method-channel call) rather than erroring when they're missing.
  permissionDenied,

  /// The phone's Bluetooth radio itself is off.
  bluetoothOff,

  /// Bluetooth Classic (SPP) connect attempt exceeded [BluetoothPrinterService._connectTimeout] —
  /// thermal printers can legitimately take a few seconds to accept a
  /// connection, but an unreachable/powered-off printer would otherwise
  /// hang the UI indefinitely instead of failing.
  timeout,

  /// Permission granted, Bluetooth on, connect attempt returned/threw
  /// without a more specific reason (e.g. printer off, out of range,
  /// already connected to another phone).
  unknown,
}

class PrinterConnectResult {
  final bool success;
  final PrinterConnectError? error;
  const PrinterConnectResult.ok()
      : success = true,
        error = null;
  const PrinterConnectResult.fail(this.error) : success = false;
}

/// One structural element of a receipt, in print order. This is the single
/// source of truth for "what a receipt contains" — [buildReceiptPlan] builds
/// it once from [InvoicePrintData], and both the real ESC/POS byte encoder
/// ([BluetoothPrinterService._buildTicket]) and the on-screen preview
/// (ReceiptPreviewView) render from it, so they can never structurally drift
/// apart from each other.
sealed class ReceiptElement {}

class ReceiptTextLine extends ReceiptElement {
  final String text;
  final bool bold;
  final ReceiptAlign align;
  ReceiptTextLine(this.text, {this.bold = false, this.align = ReceiptAlign.left});
}

class ReceiptSeparatorLine extends ReceiptElement {}

class ReceiptLogoElement extends ReceiptElement {
  final String logoUrl;
  ReceiptLogoElement(this.logoUrl);
}

class ReceiptQrElement extends ReceiptElement {
  final String data;
  ReceiptQrElement(this.data);
}

/// Builds the ordered content plan for [d]'s receipt — every line, in the
/// same order and under the same conditions a physical thermal receipt would
/// print them (logo, header, invoice#/date, customer+phone, delegate name,
/// items table, sales/discount/returns/replacement totals, إجمالي المديونية/
/// الصافي المستحق/المدفوع/المتبقي, feedback QR code, footer). A return whose
/// refund_method is in_kind_replacement additionally prints its replacement
/// item as a linked "← بدل: ..." line right under it (see the returns loop
/// below), and its value surfaces as its own "بدل عيني: +..." totals line
/// distinct from the plain "المرتجعات: -..." deduction line every return
/// (cash or in-kind) still contributes to. Trailing paper-feed blank lines
/// and the cut command are print-mechanics only, not content, so they're
/// added by [BluetoothPrinterService._buildTicket] directly rather than here.
List<ReceiptElement> buildReceiptPlan(InvoicePrintData d) {
  final elements = <ReceiptElement>[];
  void addLine(String text, {bool bold = false, ReceiptAlign align = ReceiptAlign.left}) =>
      elements.add(ReceiptTextLine(text, bold: bold, align: align));
  void separator() => elements.add(ReceiptSeparatorLine());

  // 1. Logo (greyscale receipt logo)
  if (d.logoUrl != null && d.logoUrl!.isNotEmpty) {
    elements.add(ReceiptLogoElement(d.logoUrl!));
  }

  // 2. Company name + welcome header text
  if (d.companyName.isNotEmpty) {
    addLine(d.companyName, bold: true, align: ReceiptAlign.center);
  }
  if (d.headerText != null && d.headerText!.isNotEmpty) {
    addLine(d.headerText!, align: ReceiptAlign.center);
  }
  separator();

  // 3. Invoice number + date/time
  addLine('رقم الفاتورة: ${d.invoiceNumber}');
  addLine('التاريخ: ${DateFormat('yyyy/MM/dd – HH:mm').format(d.issuedAt)}');
  separator();

  // 4. Customer name + region (customer-facing receipt shows region, not
  // phone — the phone number stays admin-only elsewhere in the app).
  // Omitted entirely when the customer has no region set, matching the
  // conditional-omission convention used for discount/returns/debt lines.
  addLine('العميل : ${d.clientName}');
  if (d.clientRegion != null && d.clientRegion!.isNotEmpty) {
    addLine('المنطقة : ${d.clientRegion}');
  }

  // 5. Delegate (representative) name
  addLine('المندوب: ${d.delegateName}');
  separator();

  // 6. Items table: الصنف | الوحدة | الكمية | السعر | الإجمالي
  addLine(_row5('الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'), bold: true);
  separator();

  for (final item in d.salesItems) {
    final nameLines = _wrapText(item.productName, 12);
    for (var i = 0; i < nameLines.length; i++) {
      if (i == 0) {
        addLine(_row5(
          nameLines[i],
          item.unit,
          item.quantity.toStringAsFixed(2),
          item.unitPrice.toStringAsFixed(2),
          item.subtotal.toStringAsFixed(2),
        ));
      } else {
        addLine(nameLines[i]);
      }
    }
  }

  if (d.returnedItems.isNotEmpty) {
    separator();
    addLine('المرتجعات:', bold: true);
    for (final ret in d.returnedItems) {
      final nameLines = _wrapText(ret.productName, 12);
      for (var i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          addLine(_row5(
            nameLines[i],
            ret.unit,
            '-${ret.quantity.toStringAsFixed(2)}',
            ret.unitPrice.toStringAsFixed(2),
            ret.subtotal.toStringAsFixed(2),
          ));
        } else {
          addLine(nameLines[i]);
        }
      }
      // An in-kind-replacement return hands the customer a different
      // product instead of cash — printed as a linked pair right under the
      // returned line so it reads as one swap, distinct from a plain
      // cash-refunded return (which ends here with nothing further).
      if (ret.refundMethod == 'in_kind_replacement' && ret.replacementProductName != null) {
        addLine('  ← بدل: ${ret.replacementProductName} '
            '(${(ret.replacementQuantity ?? 0).toStringAsFixed(2)} ${ret.replacementUnit ?? ''}) '
            '= ${(ret.replacementSubtotal ?? 0).toStringAsFixed(2)}');
      }
    }
  }

  separator();

  // 7. Gross sales total (before discount/returns)
  addLine('إجمالي المبيعات: ${d.grossSales.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 8. Discount — only when present
  if (d.discountAmount > 0) {
    addLine('الخصم: -${d.discountAmount.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  }

  // 9. Returns — only when this invoice includes returns. Value of ALL
  // returns regardless of refund_method — still "goods that came back".
  if (d.totalReturns > 0) {
    addLine('المرتجعات: -${d.totalReturns.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  }

  // 9b. In-kind-replacement additions — only when this invoice has any.
  // A return with refund_method=in_kind_replacement never reduces cash
  // owed on its own (see #9 above, which still counts its value); instead
  // the replacement product's own value is added here — together #9 and
  // this line explain net_total exactly (net effect of a swap = this line
  // minus that return's own share of #9).
  if (d.replacementItemsTotal > 0) {
    addLine('بدل عيني: +${d.replacementItemsTotal.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  }

  separator();

  // 10. Customer's PRIOR outstanding balance — BEFORE this invoice's own
  // effect is applied — only shown when there was existing debt.
  if (d.priorDebt > 0) {
    addLine('إجمالي المديونية: ${d.priorDebt.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  }

  // 11. Total now due against this invoice: its own net total plus
  // whatever the customer already owed beforehand.
  final netDue = d.netTotal + d.priorDebt;
  addLine('الصافي المستحق: ${netDue.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 12. Cash received
  addLine('المدفوع: ${d.cashReceived.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 13. What's left of #11 after cash received — equals the customer's
  // actual new balance (see DelegateInvoiceController::store()'s
  // debtDelta/debtReduction logic). Mutually exclusive with the
  // overpayment message: an overpayment beyond the prior debt can make
  // this negative, in which case debt_reduction (the actual amount paid
  // off) is shown instead rather than a computed negative "remaining".
  final remaining = netDue - d.cashReceived;
  if (remaining > 0) {
    addLine('المتبقي: ${remaining.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  } else if (d.debtReduction > 0) {
    addLine('تم سداد ${d.debtReduction.toStringAsFixed(2)} ج.م من دين العميل السابق',
        bold: true, align: ReceiptAlign.right);
  }

  // 14. QR code linking to the public feedback/complaints form — the SAME
  // fixed URL on every single receipt (kFeedbackUrl), placed near the
  // footer with a short label above it.
  separator();
  addLine('امسح للشكاوى والمقترحات', align: ReceiptAlign.center);
  elements.add(ReceiptQrElement(kFeedbackUrl));

  // 15. Footer text
  if (d.footerText != null && d.footerText!.isNotEmpty) {
    separator();
    addLine(d.footerText!, align: ReceiptAlign.center);
  }

  return elements;
}

/// Fixed-width 5-column row: name | unit | qty | price | total.
String _row5(String name, String unit, String qty, String price, String total) {
  final n = name.padRight(12).substring(0, 12);
  final u = unit.padRight(6).substring(0, 6);
  final q = qty.padLeft(6);
  final p = price.padLeft(8);
  final t = total.padLeft(10);
  return '$n$u$q$p$t';
}

List<String> _wrapText(String text, int maxWidth) {
  if (text.length <= maxWidth) return [text];
  final lines = <String>[];
  var remaining = text;
  while (remaining.length > maxWidth) {
    lines.add(remaining.substring(0, maxWidth));
    remaining = remaining.substring(maxWidth);
  }
  if (remaining.isNotEmpty) lines.add(remaining);
  return lines;
}

/// One already-measured piece of [BluetoothPrinterService._renderReceiptImage]'s
/// layout: its final height, and a callback that paints it onto the receipt
/// [Canvas] at a given `y`. Building the whole layout as a list of these
/// first (each already knows its own height from a completed [TextPainter]
/// layout pass) is what lets the canvas's total height be known before a
/// single pixel is drawn — a [ui.PictureRecorder]'s canvas can be painted
/// at any coordinate, but converting it to a fixed-size image up front
/// requires that size in advance.
class _ReceiptDrawOp {
  final double height;
  final void Function(Canvas canvas, double y) paint;
  _ReceiptDrawOp(this.height, this.paint);
}

class BluetoothPrinterService {
  /// Bluetooth Classic (SPP) connect can legitimately take a few seconds on
  /// a real thermal printer — long enough that a short timeout would read
  /// as an intermittent failure, but bounded so an unreachable printer
  /// can't hang the UI forever (see [PrinterConnectError.timeout] doc).
  static const _connectTimeout = Duration(seconds: 12);

  /// Requests BLUETOOTH_CONNECT + BLUETOOTH_SCAN (Android 12+ dangerous
  /// runtime permissions — declaring them in the manifest alone does not
  /// grant them). On pre-Android-12 devices permission_handler reports
  /// these as already granted since the OS has no such runtime permission
  /// there, so this is safe to call unconditionally regardless of SDK
  /// version.
  Future<bool> ensureBluetoothPermission() async {
    final statuses = await [
      ph.Permission.bluetoothConnect,
      ph.Permission.bluetoothScan,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<List<BluetoothInfo>> discoverDevices() async {
    if (!await ensureBluetoothPermission()) return [];
    try {
      // Defensive timeout: the native plugin silently never resolves this
      // call when BLUETOOTH_CONNECT is missing instead of throwing, so a
      // permission revoked after ensureBluetoothPermission() returned
      // (e.g. via OS settings mid-session) would otherwise hang forever.
      return await PrintBluetoothThermal.pairedBluetooths.timeout(_connectTimeout);
    } catch (_) {
      return [];
    }
  }

  /// Connects to [macAddress], surfacing *why* a failure happened via
  /// [PrinterConnectResult.error] instead of collapsing every cause into a
  /// single generic false. Always disconnects any stale/half-open
  /// connection first and retries once (also disconnect-first) before
  /// giving up, since a previous connection left dangling by a killed app
  /// or a dropped socket is a common intermittent-failure cause on
  /// Bluetooth Classic thermal printers.
  Future<PrinterConnectResult> connect(String macAddress) async {
    if (!await ensureBluetoothPermission()) {
      return const PrinterConnectResult.fail(PrinterConnectError.permissionDenied);
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      return const PrinterConnectResult.fail(PrinterConnectError.bluetoothOff);
    }

    Future<PrinterConnectResult> attempt() async {
      await disconnect();
      try {
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress)
            .timeout(_connectTimeout);
        return ok
            ? const PrinterConnectResult.ok()
            : const PrinterConnectResult.fail(PrinterConnectError.unknown);
      } on TimeoutException {
        return const PrinterConnectResult.fail(PrinterConnectError.timeout);
      } catch (_) {
        return const PrinterConnectResult.fail(PrinterConnectError.unknown);
      }
    }

    final first = await attempt();
    if (first.success) return first;
    return attempt();
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect.timeout(_connectTimeout);
    } catch (_) {}
    _connectedDevice = null;
  }

  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus.timeout(_connectTimeout);
    } catch (_) {
      return false;
    }
  }

  /// The printer this service believes it's currently connected to, kept
  /// alive on this DI singleton across print_invoice_page.dart's widget
  /// lifecycle — the page gets torn down and rebuilt every time the user
  /// navigates away and back, but this service does not, so a printer
  /// connected on a previous visit doesn't need re-selecting/re-connecting.
  BluetoothInfo? _connectedDevice;
  BluetoothInfo? get connectedDevice => _connectedDevice;

  /// Connects to [device] only if not already connected to it — verified
  /// via [isConnected] rather than trusting [_connectedDevice] alone, since
  /// a real Bluetooth Classic link can silently drop (printer powered off,
  /// walked out of range) without this app being told. Only falls through
  /// to the full disconnect-before-connect [connect] sequence when a
  /// genuinely new connection is needed (different printer, or [isConnected]
  /// reports false despite matching [_connectedDevice]) — this is what keeps
  /// repeat prints from paying a full reconnect handshake every time.
  Future<PrinterConnectResult> ensureConnected(BluetoothInfo device) async {
    if (_connectedDevice?.macAdress == device.macAdress && await isConnected) {
      return const PrinterConnectResult.ok();
    }
    final result = await connect(device.macAdress);
    _connectedDevice = result.success ? device : null;
    return result;
  }

  /// Prints [data] over whatever connection is already live. When [device]
  /// is supplied and the write fails — the "persistent" connection turning
  /// out to be stale (printer turned off/out of range mid-session) — falls
  /// back to the full reconnect-and-retry flow instead of just failing
  /// silently, then retries the SAME already-rendered ticket once (no need
  /// to re-render the receipt bitmap just because the printer needed a
  /// fresh handshake).
  Future<bool> printInvoice(InvoicePrintData data, {BluetoothInfo? device}) async {
    final List<int> ticket;
    try {
      ticket = await _buildTicket(data);
    } catch (e) {
      debugPrint('Print render error: $e');
      return false;
    }

    if (await _writeTicket(ticket)) return true;
    if (device == null) return false;

    debugPrint('Print write failed on presumed-live connection, retrying with full reconnect');
    final reconnect = await connect(device.macAdress);
    _connectedDevice = reconnect.success ? device : null;
    if (!reconnect.success) return false;
    return _writeTicket(ticket);
  }

  Future<bool> _writeTicket(List<int> ticket) async {
    try {
      // Same defensive timeout as connect()/disconnect() — a receipt bitmap
      // is a much larger payload than a bare connect handshake, so this
      // gets more headroom.
      return await PrintBluetoothThermal.writeBytes(ticket).timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('Print error: $e');
      return false;
    }
  }

  /// Builds the full print ticket. The *entire* receipt — logo, header,
  /// invoice info, items table, totals, footer — is rendered once as a
  /// single bitmap ([_renderReceiptImage]) and sent as one or more ESC/POS
  /// raster-image commands, instead of the raw ESC/POS text commands this
  /// used to send line-by-line.
  ///
  /// Why: a real physical print showed the logo rendering fine (it already
  /// went through this bitmap path) but every line of Arabic *text* printing
  /// as garbled/wrong characters — thermal printers generally have no
  /// correct Arabic codepage for their built-in text commands, so raw text
  /// bytes sent via ESC/POS's text command are misinterpreted regardless of
  /// encoding. Routing everything through Flutter's own text
  /// shaping/painting (the same engine that already renders Arabic
  /// correctly on-screen in InvoicePreviewPage) and sending the result as
  /// pixels sidesteps that entirely — the printer never has to interpret a
  /// single Arabic character.
  Future<List<int>> _buildTicket(InvoicePrintData d) async {
    final List<int> bytes = [];
    void addBytes(List<int> b) => bytes.addAll(b);
    void line(String text) => addBytes([...text.codeUnits, 0x0A]);

    // Initialize printer
    addBytes([0x1B, 0x40]);

    final receiptImage = await _renderReceiptImage(d);
    addBytes(_toChunkedRasterCommands(receiptImage));

    line('');
    line('');
    line('');

    // Feed and cut: GS V 66 3
    addBytes([0x1D, 0x56, 0x42, 0x03]);

    return bytes;
  }

  /// Test-only seam onto [_renderReceiptImage] — kept private/underscored
  /// internally so nothing outside this file relies on the rendering
  /// pipeline's shape, but exposed for a widget test to exercise the real
  /// Canvas/TextPainter layout code (privacy in Dart is per-file, so a test
  /// file in test/ genuinely cannot call a leading-underscore member here).
  /// [styleBuilder] lets a test skip google_fonts' network font fetch
  /// entirely (see _renderReceiptImage's own doc comment) — omit it to test
  /// against the real Cairo font.
  @visibleForTesting
  Future<img.Image> renderReceiptImageForTest(
    InvoicePrintData d, {
    TextStyle Function({required double size, required bool bold})? styleBuilder,
  }) =>
      _renderReceiptImage(d, styleBuilder: styleBuilder);

  /// Renders [d]'s full receipt — via [buildReceiptPlan], the same content
  /// plan the on-screen preview (InvoicePreviewPage/ReceiptPreviewCard)
  /// renders from — onto a single white-background RGBA image at
  /// [_logoWidthDots] width (the same safe width already used for the
  /// logo). Text is laid out/painted with Flutter's own TextPainter (Cairo,
  /// matching the app's theme font), so Arabic shaping/joining is correct;
  /// [_toChunkedRasterCommands] later thresholds the whole image (text,
  /// logo and all) to 1-bit black/white for the printer, exactly like the
  /// logo-only path already did.
  ///
  /// The items/returns table is special-cased exactly like
  /// invoice_preview_page.dart's ReceiptPreviewCard does: buildReceiptPlan()
  /// bakes item rows into fixed-width monospace strings meant for a printer
  /// text column grid, which isn't meaningful once we're laying out real
  /// wrapped/shaped text, so a proper table is drawn directly from
  /// d.salesItems/d.returnedItems instead, and every raw printer-formatted
  /// item line buildReceiptPlan() emitted for that span is skipped.
  Future<img.Image> _renderReceiptImage(
    InvoicePrintData d, {
    TextStyle Function({required double size, required bool bold})? styleBuilder,
  }) async {
    final double width = d.paperWidthDots.toDouble();
    const double hPad = 10;
    final double contentWidth = width - hPad * 2;

    final ops = <_ReceiptDrawOp>[];

    // Overridable only so a widget test can inject a plain TextStyle and
    // avoid google_fonts' network font fetch — production always uses the
    // real Cairo builder below (same font the rest of the app's theme uses).
    final buildTextStyle = styleBuilder ??
        ({required double size, required bool bold}) => GoogleFonts.cairo(
              fontSize: size,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black,
              height: 1.25,
            );
    TextStyle textStyle({required double size, required bool bold}) => buildTextStyle(
          size: size,
          bold: bold,
        );

    void addText(String text,
        {required double size, bool bold = false, ReceiptAlign align = ReceiptAlign.left}) {
      // Mirrors invoice_preview_page.dart's _ReceiptLine: every non-centered
      // line reads right-aligned RTL (buildReceiptPlan's ReceiptAlign.left
      // default is a leftover from the old raw-text printer format and
      // isn't meaningful once real Arabic text is being laid out — the
      // on-screen preview already ignores it the same way).
      final centered = align == ReceiptAlign.center;
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle(size: size, bold: bold)),
        textDirection: TextDirection.rtl,
        textAlign: centered ? TextAlign.center : TextAlign.right,
      )..layout(maxWidth: contentWidth);
      // TextPainter.width after layout(maxWidth: ...) is the text's own
      // measured width, NOT the maxWidth box — so painting at a fixed
      // Offset(hPad, y) always left-anchors the glyphs regardless of
      // textAlign above (textAlign only matters if this paragraph actually
      // wraps to multiple lines of differing width). This is the real
      // physical-print bug: every line rendered flush-left instead of
      // right-aligned. Fixed by computing x from the measured width
      // ourselves, exactly like addRow/cellPainter below already does for
      // the items table.
      final double x = centered ? (width - tp.width) / 2 : (width - hPad - tp.width);
      ops.add(_ReceiptDrawOp(tp.height + 6, (canvas, y) => tp.paint(canvas, Offset(x, y))));
    }

    void addSeparator() {
      ops.add(_ReceiptDrawOp(16, (canvas, y) {
        canvas.drawLine(
          Offset(hPad, y + 8),
          Offset(width - hPad, y + 8),
          Paint()
            ..color = Colors.black
            ..strokeWidth = 1.4,
        );
      }));
    }

    Future<void> addLogo(String logoUrl) async {
      final cacheKey = '$logoUrl@${width.toInt()}';
      var uiImage = _logoImageCache[cacheKey];
      if (uiImage == null) {
        final resized = await _fetchAndResizeLogo(logoUrl, width: width.toInt());
        if (resized == null) return;
        uiImage = await _decodeUiImage(resized);
        _logoImageCache[cacheKey] = uiImage;
      }
      final h = uiImage.height.toDouble();
      ops.add(_ReceiptDrawOp(
          h + 12, (canvas, y) => canvas.drawImage(uiImage!, Offset(0, y), Paint())));
    }

    Future<void> addQr(String qrData) async {
      final uiImage = await _qrImage(qrData);
      final h = uiImage.height.toDouble();
      final x = (width - uiImage.width) / 2;
      ops.add(_ReceiptDrawOp(
          h + 10, (canvas, y) => canvas.drawImage(uiImage, Offset(x, y), Paint())));
    }

    // Right-to-left column order (rightmost = الصنف, leftmost = الإجمالي).
    // Widened relative to invoice_preview_page.dart's on-screen
    // _columnWidths (which has much more horizontal room to work with) —
    // on a real 58mm/384-dot print the old [3.2, 1.1, 1.1, 1.4, 1.6] ratio
    // left الوحدة/الكمية/السعر too narrow for their own header labels at
    // 16px bold, clipping them mid-glyph ("الوحدة" → "الوحـ").
    const columnFlex = [2.6, 1.4, 1.2, 1.5, 1.7];
    final columnFlexTotal = columnFlex.reduce((a, b) => a + b);
    final columnWidths =
        columnFlex.map((f) => contentWidth * f / columnFlexTotal).toList(growable: false);
    final columnRightEdges = <double>[];
    var edgeCursor = width - hPad;
    for (final w in columnWidths) {
      columnRightEdges.add(edgeCursor);
      edgeCursor -= w;
    }

    // No maxLines/ellipsis on any column: wider columns above make a
    // header/cell wrapping to a second line the rare case rather than the
    // norm, but when it does happen the row simply grows taller (addRow's
    // rowHeight is the max of its cells' measured heights) instead of ever
    // silently clipping text — the failure mode this whole table rewrite
    // exists to eliminate.
    TextPainter cellPainter(String text, int col, {required bool bold, required double size}) {
      final isNameCol = col == 0;
      return TextPainter(
        text: TextSpan(text: text, style: textStyle(size: size, bold: bold)),
        textDirection: TextDirection.rtl,
        textAlign: isNameCol ? TextAlign.right : TextAlign.center,
      )..layout(maxWidth: columnWidths[col] - 4);
    }

    void addRow(List<TextPainter> cells, {required double vPad}) {
      final rowHeight = cells.map((p) => p.height).reduce((a, b) => a > b ? a : b);
      ops.add(_ReceiptDrawOp(rowHeight + vPad, (canvas, y) {
        for (var c = 0; c < cells.length; c++) {
          final p = cells[c];
          final x = c == 0
              ? columnRightEdges[c] - p.width
              : columnRightEdges[c] - columnWidths[c] + (columnWidths[c] - p.width) / 2;
          p.paint(canvas, Offset(x, y));
        }
      }));
    }

    void addItemsTable(List<PrintLineItem> items, {bool isReturns = false}) {
      const headers = ['الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'];
      addRow([for (var c = 0; c < 5; c++) cellPainter(headers[c], c, bold: true, size: 14)],
          vPad: 8);
      addSeparator();
      for (final item in items) {
        final qtyText =
            isReturns ? '-${item.quantity.toStringAsFixed(2)}' : item.quantity.toStringAsFixed(2);
        final cells = [
          item.productName,
          item.unit,
          qtyText,
          item.unitPrice.toStringAsFixed(2),
          item.subtotal.toStringAsFixed(2),
        ];
        addRow([
          for (var c = 0; c < 5; c++)
            cellPainter(cells[c], c, bold: c == 0 || c == 4, size: kReceiptBoldTextSize)
        ], vPad: 10);
      }
    }

    final elements = buildReceiptPlan(d);
    var i = 0;
    while (i < elements.length) {
      final el = elements[i];

      if (el is ReceiptTextLine && el.text.trimLeft().startsWith('الصنف')) {
        addItemsTable(d.salesItems);
        if (d.returnedItems.isNotEmpty) {
          addSeparator();
          addText('المرتجعات:', bold: true, size: kReceiptBoldTextSize);
          addItemsTable(d.returnedItems, isReturns: true);
        }
        i++;
        while (i < elements.length) {
          final next = elements[i];
          if (next is ReceiptTextLine && next.text.startsWith('إجمالي المبيعات:')) break;
          i++;
        }
        continue;
      }

      switch (el) {
        case ReceiptLogoElement(:final logoUrl):
          await addLogo(logoUrl);
        case ReceiptQrElement(:final data):
          await addQr(data);
        case ReceiptSeparatorLine():
          addSeparator();
        case ReceiptTextLine(:final text, :final bold, :final align):
          final isHero = text.startsWith('الصافي المستحق:');
          final isCentered = align == ReceiptAlign.center;
          final double size;
          if (isCentered && bold) {
            size = 30; // company name — receipt title
          } else if (isCentered) {
            size = 20; // header/footer welcome text
          } else if (isHero) {
            size = 26;
          } else if (bold) {
            size = kReceiptBoldTextSize; // rest of the totals block
          } else {
            size = 22;
          }
          addText(text, bold: bold, align: align, size: size);
      }
      i++;
    }

    final totalHeight = (ops.fold<double>(0, (s, o) => s + o.height) + 20).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, totalHeight.toDouble()), Paint()..color = Colors.white);
    var y = 10.0;
    for (final op in ops) {
      op.paint(canvas, y);
      y += op.height;
    }
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(width.toInt(), totalHeight);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    return img.Image.fromBytes(
      width: width.toInt(),
      height: totalHeight,
      bytes: byteData!.buffer,
      numChannels: 4,
    );
  }

  /// Decoded+resized receipt logo, keyed by `'$logoUrl@$widthDots'` — the
  /// same [InvoicePrintData.logoUrl] is printed over and over for every
  /// invoice, and (unless the admin re-uploads a logo) never changes, so a
  /// real network fetch (when `logoUrl` isn't an inline `data:` URI) plus
  /// decode/resize is pure repeated work on every single print. Instance-
  /// level (not static, unlike [_cachedQrImage]) since it holds actual image
  /// bytes worth potentially several logos' worth of memory, and this
  /// service is already a DI singleton so one cache per app run is enough.
  final Map<String, ui.Image> _logoImageCache = {};

  /// Renders [kFeedbackUrl] as a QR code image once and caches it — every
  /// receipt everywhere encodes the exact same fixed URL, so there's no
  /// reason to re-run QR generation/rasterization on every single print or
  /// preview. Static (not instance-level) so the cache survives regardless
  /// of how many [BluetoothPrinterService] instances get created.
  static ui.Image? _cachedQrImage;
  Future<ui.Image> _qrImage(String data) async {
    final cached = _cachedQrImage;
    if (cached != null) return cached;
    final painter = QrPainter(data: data, version: QrVersions.auto, gapless: true);
    final image = await painter.toImage(_qrSizeDots);
    _cachedQrImage = image;
    return image;
  }

  /// Decodes an [img.Image] (already-resized logo pixels) into a [ui.Image]
  /// so it can be drawn onto the receipt [Canvas] with `drawImage` —
  /// avoids a PNG-encode/decode round trip since [img.Image.getBytes] can
  /// hand back raw RGBA directly.
  Future<ui.Image> _decodeUiImage(img.Image image) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      image.getBytes(order: img.ChannelOrder.rgba),
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Thresholds [image] to 1-bit black/white (via [_isDarkOnWhite], the same
  /// alpha-aware check the logo path uses) and slices it into horizontal
  /// bands before ESC/POS-encoding each one via [_toRasterCommand] — a
  /// single GS-v-0 command for a whole multi-hundred-dot-tall receipt risks
  /// overrunning a thermal printer's print buffer, so this sends it as
  /// several shorter raster commands instead, back to back.
  List<int> _toChunkedRasterCommands(img.Image image, {int bandHeight = 200}) {
    final bytes = <int>[];
    for (var y = 0; y < image.height; y += bandHeight) {
      final h = (y + bandHeight <= image.height) ? bandHeight : image.height - y;
      final band = img.copyCrop(image, x: 0, y: y, width: image.width, height: h);
      bytes.addAll(_toRasterCommand(band));
    }
    return bytes;
  }

  /// Fetches the receipt logo (network URL or inline `data:` URI). Returns
  /// null on any failure so a broken/unreachable logo never blocks the rest
  /// of the receipt from printing/previewing.
  Future<Uint8List?> _fetchLogoBytes(String logoUrl) async {
    try {
      if (logoUrl.startsWith('data:')) {
        final base64Part = logoUrl.substring(logoUrl.indexOf(',') + 1);
        return base64Decode(base64Part);
      }
      final response = await Dio().get<List<int>>(
        logoUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } catch (e) {
      debugPrint('Logo fetch failed: $e');
      return null;
    }
  }

  Future<img.Image?> _fetchAndResizeLogo(String logoUrl, {int width = _logoWidthDots}) async {
    final bytes = await _fetchLogoBytes(logoUrl);
    if (bytes == null) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.copyResize(decoded, width: width);
  }

  /// Same fetch → resize → 1-bit threshold pipeline as the real print path,
  /// re-encoded as a PNG for on-screen preview, so the preview shows exactly
  /// what the printer will produce rather than the original color logo.
  Future<Uint8List?> renderLogoPreviewPng(String logoUrl) async {
    final resized = await _fetchAndResizeLogo(logoUrl);
    if (resized == null) return null;
    final mono = img.Image(width: resized.width, height: resized.height);
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final v = _isDarkOnWhite(resized.getPixel(x, y)) ? 0 : 255;
        mono.setPixelRgb(x, y, v, v, v);
      }
    }
    return Uint8List.fromList(img.encodePng(mono));
  }

  /// Encodes an [image] as an ESC/POS "GS v 0" raster bit image command
  /// (1 bit per pixel, MSB first; a set bit prints as a black dot).
  List<int> _toRasterCommand(img.Image image) {
    final widthBytes = (image.width + 7) ~/ 8;
    final data = <int>[];

    for (var y = 0; y < image.height; y++) {
      final row = List<int>.filled(widthBytes, 0);
      for (var x = 0; x < image.width; x++) {
        if (_isDarkOnWhite(image.getPixel(x, y))) {
          row[x >> 3] |= (0x80 >> (x & 7));
        }
      }
      data.addAll(row);
    }

    return [
      0x1D, 0x76, 0x30, 0x00,
      widthBytes & 0xFF, (widthBytes >> 8) & 0xFF,
      image.height & 0xFF, (image.height >> 8) & 0xFF,
      ...data,
    ];
  }

  /// Whether [pixel] should print/render as a black dot once composited onto
  /// a plain white receipt background.
  ///
  /// The logo source PNGs here are genuinely transparent (verified directly
  /// against the uploaded `receipt_settings.company_logo`/`company_logo_color`
  /// files), but a transparent pixel's leftover RGB channel values are
  /// whatever the exporting tool happened to leave behind — commonly
  /// (0,0,0), but not always (one of these logos' transparent palette entry
  /// is a dark green (71,112,76)). Thresholding `pixel.luminance` directly,
  /// as this used to, ignored `pixel.a` entirely: any transparent pixel
  /// whose incidental RGB was merely dark (luminance below
  /// [_blackThreshold]) — which covers most of a logo's transparent
  /// background — printed as solid black, regardless of the logo's actual
  /// visible color. Alpha-compositing onto white FIRST, then thresholding
  /// the *result*, is the correct fix: a fully transparent pixel always
  /// composites to pure white (never black) no matter what color garbage
  /// its RGB channels hold, and partially-transparent edge pixels fade
  /// smoothly toward white instead of a hard on/off cutoff.
  bool _isDarkOnWhite(img.Pixel pixel) {
    final maxVal = pixel.maxChannelValue;
    final alpha = pixel.a / maxVal;
    final compositedLuminance = pixel.luminance * alpha + maxVal * (1 - alpha);
    return compositedLuminance < _blackThreshold;
  }
}

class InvoicePrintData {
  final String invoiceNumber;
  final String clientName;
  final String clientPhone;
  final bool showPhone;
  // Customer's region name (Customer.customer_region_id/region()), shown on
  // the customer-facing receipt in place of the phone number. Null/empty
  // when the customer has no region set — the receipt line is then omitted
  // entirely, never rendered as an empty "المنطقة: —".
  final String? clientRegion;
  final String delegateName;
  final DateTime issuedAt;
  final List<PrintLineItem> salesItems;
  final List<PrintLineItem> returnedItems;
  final double grossSales;
  final double discountAmount;
  final double totalReturns;
  // Sum of in-kind-replacement returns' replacement-product value — see
  // DelegateInvoiceController::store()'s net_total formula. 0 when every
  // return (if any) is a plain cash refund, matching prior receipts exactly.
  final double replacementItemsTotal;
  final double netTotal;
  final double cashReceived;
  final double balanceAddedToDebt;
  // Customer's outstanding balance BEFORE this invoice's own effect —
  // drives "إجمالي المديونية"/"الصافي المستحق" (see buildReceiptPlan).
  final double priorDebt;
  // Amount of priorDebt actually paid off by an overpayment on this
  // invoice — mutually exclusive with a positive "المتبقي" in the receipt.
  final double debtReduction;
  final String companyName;
  final String? headerText;
  final String? footerText;
  final String? logoUrl;
  // Printer raster width in dots — see rasterWidthDotsForPaper. Defaults to
  // the 58mm width so existing callers/tests that don't pass it keep the
  // prior fixed-width behavior.
  final int paperWidthDots;

  const InvoicePrintData({
    required this.invoiceNumber,
    required this.clientName,
    required this.clientPhone,
    this.showPhone = true,
    this.clientRegion,
    required this.delegateName,
    required this.issuedAt,
    required this.salesItems,
    required this.returnedItems,
    required this.grossSales,
    this.discountAmount = 0,
    required this.totalReturns,
    this.replacementItemsTotal = 0,
    required this.netTotal,
    required this.cashReceived,
    required this.balanceAddedToDebt,
    this.priorDebt = 0,
    this.debtReduction = 0,
    this.companyName = '',
    this.headerText,
    this.footerText,
    this.logoUrl,
    this.paperWidthDots = _logoWidthDots,
  });

  /// Builds print data from a raw `/delegate/invoices/{id}` JSON payload —
  /// the one place both the real print flow (print_invoice_page.dart) and
  /// the on-screen preview construct an [InvoicePrintData], so they always
  /// work from identical data.
  factory InvoicePrintData.fromInvoiceJson(
    Map<String, dynamic> invoiceData, {
    bool showPhone = true,
    String companyName = '',
    String? headerText,
    String? footerText,
    String? logoUrl,
    String paperWidth = '58mm',
  }) {
    final customer = invoiceData['customer'] as Map<String, dynamic>? ?? {};
    final delegate = invoiceData['delegate'] as Map<String, dynamic>? ?? {};
    final items = invoiceData['items'] as List? ?? [];
    final returns = invoiceData['returns'] as List? ?? [];

    PrintLineItem toLineItem(dynamic e) {
      final m = e as Map<String, dynamic>;
      final p = m['product'] as Map<String, dynamic>? ?? {};
      // Only present on a return whose refund_method is
      // in_kind_replacement (see DelegateInvoiceReturn::replacementProduct).
      final replacementProduct = m['replacement_product'] as Map<String, dynamic>?;
      return PrintLineItem(
        productName: p['name'] as String? ?? '',
        unit: p['unit'] as String? ?? '',
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        subtotal: (m['subtotal'] as num).toDouble(),
        refundMethod: m['refund_method'] as String? ?? 'cash',
        replacementProductName: replacementProduct?['name'] as String?,
        replacementUnit: replacementProduct?['unit'] as String?,
        replacementQuantity: (m['replacement_quantity'] as num?)?.toDouble(),
        replacementUnitPrice: (m['replacement_unit_price'] as num?)?.toDouble(),
        replacementSubtotal: (m['replacement_subtotal'] as num?)?.toDouble(),
      );
    }

    return InvoicePrintData(
      invoiceNumber: invoiceData['invoice_number'] as String? ?? '',
      clientName: customer['name'] as String? ?? '',
      clientPhone: customer['phone'] as String? ?? '',
      showPhone: showPhone,
      clientRegion: (customer['region'] as Map<String, dynamic>?)?['name'] as String?,
      delegateName: delegate['name'] as String? ?? 'مندوب',
      issuedAt: parseServerDateTime(invoiceData['created_at'] as String?),
      salesItems: items.map(toLineItem).toList(),
      returnedItems: returns.map(toLineItem).toList(),
      grossSales: (invoiceData['gross_sales_total'] as num? ?? 0).toDouble(),
      discountAmount: (invoiceData['discount_amount'] as num? ?? 0).toDouble(),
      totalReturns: (invoiceData['total_returns'] as num? ?? 0).toDouble(),
      replacementItemsTotal: (invoiceData['replacement_items_total'] as num? ?? 0).toDouble(),
      netTotal: (invoiceData['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (invoiceData['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt: (invoiceData['balance_added_to_debt'] as num? ?? 0).toDouble(),
      priorDebt: (invoiceData['prior_debt'] as num? ?? 0).toDouble(),
      debtReduction: (invoiceData['debt_reduction'] as num? ?? 0).toDouble(),
      companyName: companyName,
      headerText: headerText,
      footerText: footerText,
      logoUrl: logoUrl,
      paperWidthDots: rasterWidthDotsForPaper(paperWidth),
    );
  }
}

class PrintLineItem {
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  // Only meaningful for a RETURN line — 'cash' (default) or
  // 'in_kind_replacement'. Drives whether buildReceiptPlan prints this
  // return as a plain deduction line (as always) or a linked
  // "مرتجع: X ← بدل: Y" pair with the fields below.
  final String refundMethod;
  final String? replacementProductName;
  final String? replacementUnit;
  final double? replacementQuantity;
  final double? replacementUnitPrice;
  final double? replacementSubtotal;
  const PrintLineItem({
    required this.productName,
    this.unit = '',
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.refundMethod = 'cash',
    this.replacementProductName,
    this.replacementUnit,
    this.replacementQuantity,
    this.replacementUnitPrice,
    this.replacementSubtotal,
  });
}
