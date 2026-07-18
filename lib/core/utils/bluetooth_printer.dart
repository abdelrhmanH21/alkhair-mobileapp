import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

const int _charsPerLine = 42; // standard 80mm ESC/POS columns
// Safe raster width for both 58mm and 80mm printers (no per-printer paper
// width is plumbed into this flow yet — see ReceiptSetting.paper_width).
const int _logoWidthDots = 384;
// Luminance below this prints as a black dot — shared by the real ESC/POS
// rasterizer and the on-screen preview's logo rendering so both show the
// exact same monochrome conversion.
const int _blackThreshold = 160;

enum ReceiptAlign { left, center, right }

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

/// Builds the ordered content plan for [d]'s receipt — every line, in the
/// same order and under the same conditions a physical thermal receipt would
/// print them (logo, header, invoice#/date, customer+phone, delegate name,
/// items table, sales/discount/returns totals, إجمالي المديونية/الصافي
/// المستحق/المدفوع/المتبقي, footer). Trailing paper-feed blank lines and the
/// cut command are print-mechanics only, not content, so they're added by
/// [BluetoothPrinterService._buildTicket] directly rather than here.
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

  // 4. Customer name + phone (respecting "إظهار رقم الهاتف")
  addLine('العميل : ${d.clientName}');
  if (d.showPhone && d.clientPhone.isNotEmpty) {
    addLine('الهاتف : ${d.clientPhone}');
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

  // 9. Returns — only when this invoice includes returns
  if (d.totalReturns > 0) {
    addLine('المرتجعات: -${d.totalReturns.toStringAsFixed(2)} ج.م',
        bold: true, align: ReceiptAlign.right);
  }

  separator();

  // 10. Overall customer debt AFTER this invoice's effect
  addLine('إجمالي المديونية: ${d.customerBalanceAfter.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 11. This invoice's own net total
  addLine('الصافي المستحق: ${d.netTotal.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 12. Cash received
  addLine('المدفوع: ${d.cashReceived.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 13. This invoice's own remaining amount only (distinct from #10)
  final remaining = d.balanceAddedToDebt > 0 ? d.balanceAddedToDebt : 0.0;
  addLine('المتبقي: ${remaining.toStringAsFixed(2)} ج.م',
      bold: true, align: ReceiptAlign.right);

  // 14. Footer text
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

class BluetoothPrinterService {
  Future<List<BluetoothInfo>> discoverDevices() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return [];
    }
  }

  Future<bool> connect(String macAddress) async {
    try {
      return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }

  Future<bool> get isConnected async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printInvoice(InvoicePrintData data) async {
    try {
      final ticket = await _buildTicket(data);
      return await PrintBluetoothThermal.writeBytes(ticket);
    } catch (e) {
      debugPrint('Print error: $e');
      return false;
    }
  }

  Future<List<int>> _buildTicket(InvoicePrintData d) async {
    final List<int> bytes = [];

    void addBytes(List<int> b) => bytes.addAll(b);

    // ESC/POS helper: add text as UTF-8 + LF
    void line(String text) {
      addBytes([...text.codeUnits, 0x0A]);
    }

    // Bold ON: ESC E 1
    void boldOn() => addBytes([0x1B, 0x45, 0x01]);
    void boldOff() => addBytes([0x1B, 0x45, 0x00]);

    // Align center: ESC a 1 / right: ESC a 2 / left: ESC a 0
    void alignCenter() => addBytes([0x1B, 0x61, 0x01]);
    void alignRight() => addBytes([0x1B, 0x61, 0x02]);
    void alignLeft() => addBytes([0x1B, 0x61, 0x00]);
    void setAlign(ReceiptAlign a) {
      switch (a) {
        case ReceiptAlign.left:
          alignLeft();
        case ReceiptAlign.center:
          alignCenter();
        case ReceiptAlign.right:
          alignRight();
      }
    }

    // Initialize printer
    addBytes([0x1B, 0x40]);

    for (final element in buildReceiptPlan(d)) {
      switch (element) {
        case ReceiptLogoElement(:final logoUrl):
          final raster = await _fetchAndRasterizeLogo(logoUrl);
          if (raster != null) {
            alignCenter();
            addBytes(raster);
            line('');
          }
        case ReceiptSeparatorLine():
          line('-' * _charsPerLine);
        case ReceiptTextLine(:final text, :final bold, :final align):
          setAlign(align);
          if (bold) boldOn();
          line(text);
          if (bold) boldOff();
      }
    }

    line('');
    line('');
    line('');

    // Feed and cut: GS V 66 3
    addBytes([0x1D, 0x56, 0x42, 0x03]);

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

  Future<img.Image?> _fetchAndResizeLogo(String logoUrl) async {
    final bytes = await _fetchLogoBytes(logoUrl);
    if (bytes == null) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.copyResize(decoded, width: _logoWidthDots);
  }

  /// Rasterizes the logo into an ESC/POS GS-v-0 monochrome bitmap command.
  Future<List<int>?> _fetchAndRasterizeLogo(String logoUrl) async {
    final resized = await _fetchAndResizeLogo(logoUrl);
    if (resized == null) return null;
    return _toRasterCommand(resized);
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
  final String delegateName;
  final DateTime issuedAt;
  final List<PrintLineItem> salesItems;
  final List<PrintLineItem> returnedItems;
  final double grossSales;
  final double discountAmount;
  final double totalReturns;
  final double netTotal;
  final double cashReceived;
  final double balanceAddedToDebt;
  final double customerBalanceAfter;
  final String companyName;
  final String? headerText;
  final String? footerText;
  final String? logoUrl;

  const InvoicePrintData({
    required this.invoiceNumber,
    required this.clientName,
    required this.clientPhone,
    this.showPhone = true,
    required this.delegateName,
    required this.issuedAt,
    required this.salesItems,
    required this.returnedItems,
    required this.grossSales,
    this.discountAmount = 0,
    required this.totalReturns,
    required this.netTotal,
    required this.cashReceived,
    required this.balanceAddedToDebt,
    this.customerBalanceAfter = 0,
    this.companyName = '',
    this.headerText,
    this.footerText,
    this.logoUrl,
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
  }) {
    final customer = invoiceData['customer'] as Map<String, dynamic>? ?? {};
    final delegate = invoiceData['delegate'] as Map<String, dynamic>? ?? {};
    final items = invoiceData['items'] as List? ?? [];
    final returns = invoiceData['returns'] as List? ?? [];

    PrintLineItem toLineItem(dynamic e) {
      final m = e as Map<String, dynamic>;
      final p = m['product'] as Map<String, dynamic>? ?? {};
      return PrintLineItem(
        productName: p['name'] as String? ?? '',
        unit: p['unit'] as String? ?? '',
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        subtotal: (m['subtotal'] as num).toDouble(),
      );
    }

    return InvoicePrintData(
      invoiceNumber: invoiceData['invoice_number'] as String? ?? '',
      clientName: customer['name'] as String? ?? '',
      clientPhone: customer['phone'] as String? ?? '',
      showPhone: showPhone,
      delegateName: delegate['name'] as String? ?? 'مندوب',
      issuedAt: DateTime.tryParse(invoiceData['created_at'] as String? ?? '') ?? DateTime.now(),
      salesItems: items.map(toLineItem).toList(),
      returnedItems: returns.map(toLineItem).toList(),
      grossSales: (invoiceData['gross_sales_total'] as num? ?? 0).toDouble(),
      discountAmount: (invoiceData['discount_amount'] as num? ?? 0).toDouble(),
      totalReturns: (invoiceData['total_returns'] as num? ?? 0).toDouble(),
      netTotal: (invoiceData['net_total'] as num? ?? 0).toDouble(),
      cashReceived: (invoiceData['cash_received'] as num? ?? 0).toDouble(),
      balanceAddedToDebt: (invoiceData['balance_added_to_debt'] as num? ?? 0).toDouble(),
      customerBalanceAfter: (customer['balance'] as num? ?? 0).toDouble(),
      companyName: companyName,
      headerText: headerText,
      footerText: footerText,
      logoUrl: logoUrl,
    );
  }
}

class PrintLineItem {
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  const PrintLineItem({
    required this.productName,
    this.unit = '',
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });
}
