import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class BluetoothPrinterService {
  static const int _charsPerLine = 42; // standard 80mm ESC/POS columns
  // Safe raster width for both 58mm and 80mm printers (no per-printer paper
  // width is plumbed into this flow yet — see ReceiptSetting.paper_width).
  static const int _logoWidthDots = 384;

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

    void separator() => line('-' * _charsPerLine);

    // Bold ON: ESC E 1
    void boldOn()  => addBytes([0x1B, 0x45, 0x01]);
    void boldOff() => addBytes([0x1B, 0x45, 0x00]);

    // Align center: ESC a 1
    void alignCenter() => addBytes([0x1B, 0x61, 0x01]);
    // Align right: ESC a 2
    void alignRight() => addBytes([0x1B, 0x61, 0x02]);
    // Align left: ESC a 0
    void alignLeft() => addBytes([0x1B, 0x61, 0x00]);

    // Initialize printer
    addBytes([0x1B, 0x40]);

    // 1. Logo (greyscale receipt logo)
    if (d.logoUrl != null && d.logoUrl!.isNotEmpty) {
      final raster = await _fetchAndRasterizeLogo(d.logoUrl!);
      if (raster != null) {
        alignCenter();
        addBytes(raster);
        line('');
      }
    }

    // 2. Company name + welcome header text
    alignCenter();
    if (d.companyName.isNotEmpty) {
      boldOn();
      line(d.companyName);
      boldOff();
    }
    if (d.headerText != null && d.headerText!.isNotEmpty) {
      line(d.headerText!);
    }
    separator();

    // 3. Invoice number + date/time
    alignLeft();
    line('رقم الفاتورة: ${d.invoiceNumber}');
    line('التاريخ: ${DateFormat('yyyy/MM/dd – HH:mm').format(d.issuedAt)}');
    separator();

    // 4. Customer name + phone (respecting "إظهار رقم الهاتف")
    line('العميل : ${d.clientName}');
    if (d.showPhone && d.clientPhone.isNotEmpty) {
      line('الهاتف : ${d.clientPhone}');
    }

    // 5. Delegate (representative) name
    line('المندوب: ${d.delegateName}');
    separator();

    // 6. Items table: الصنف | الوحدة | الكمية | السعر | الإجمالي
    boldOn();
    line(_row5('الصنف', 'الوحدة', 'الكمية', 'السعر', 'الإجمالي'));
    boldOff();
    separator();

    for (final item in d.salesItems) {
      final nameLines = _wrapText(item.productName, 12);
      for (var i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          line(_row5(
            nameLines[i],
            item.unit,
            item.quantity.toStringAsFixed(2),
            item.unitPrice.toStringAsFixed(2),
            item.subtotal.toStringAsFixed(2),
          ));
        } else {
          line(nameLines[i]);
        }
      }
    }

    if (d.returnedItems.isNotEmpty) {
      separator();
      boldOn();
      line('المرتجعات:');
      boldOff();
      for (final ret in d.returnedItems) {
        final nameLines = _wrapText(ret.productName, 12);
        for (var i = 0; i < nameLines.length; i++) {
          if (i == 0) {
            line(_row5(
              nameLines[i],
              ret.unit,
              '-${ret.quantity.toStringAsFixed(2)}',
              ret.unitPrice.toStringAsFixed(2),
              ret.subtotal.toStringAsFixed(2),
            ));
          } else {
            line(nameLines[i]);
          }
        }
      }
    }

    separator();
    alignRight();
    boldOn();

    // 7. Gross sales total (before discount/returns)
    line('إجمالي المبيعات: ${d.grossSales.toStringAsFixed(2)} ج.م');

    // 8. Discount — only when present
    if (d.discountAmount > 0) {
      line('الخصم: -${d.discountAmount.toStringAsFixed(2)} ج.م');
    }

    // 9. Returns — only when this invoice includes returns
    if (d.totalReturns > 0) {
      line('المرتجعات: -${d.totalReturns.toStringAsFixed(2)} ج.م');
    }

    separator();

    // 10. Overall customer debt AFTER this invoice's effect
    line('إجمالي المديونية: ${d.customerBalanceAfter.toStringAsFixed(2)} ج.م');

    // 11. This invoice's own net total
    line('الصافي المستحق: ${d.netTotal.toStringAsFixed(2)} ج.م');

    // 12. Cash received
    line('المدفوع: ${d.cashReceived.toStringAsFixed(2)} ج.م');

    // 13. This invoice's own remaining amount only (distinct from #10)
    final remaining = d.balanceAddedToDebt > 0 ? d.balanceAddedToDebt : 0.0;
    line('المتبقي: ${remaining.toStringAsFixed(2)} ج.م');
    boldOff();

    // 14. Footer text
    if (d.footerText != null && d.footerText!.isNotEmpty) {
      separator();
      alignCenter();
      line(d.footerText!);
    }

    line('');
    line('');
    line('');

    // Feed and cut: GS V 66 3
    addBytes([0x1D, 0x56, 0x42, 0x03]);

    return bytes;
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

  /// Fetches the receipt logo (network URL or inline `data:` URI) and
  /// rasterizes it into an ESC/POS GS-v-0 monochrome bitmap command.
  /// Returns null on any failure so a broken/unreachable logo never blocks
  /// the rest of the receipt from printing.
  Future<List<int>?> _fetchAndRasterizeLogo(String logoUrl) async {
    try {
      final Uint8List bytes;
      if (logoUrl.startsWith('data:')) {
        final base64Part = logoUrl.substring(logoUrl.indexOf(',') + 1);
        bytes = base64Decode(base64Part);
      } else {
        final response = await Dio().get<List<int>>(
          logoUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        bytes = Uint8List.fromList(response.data ?? const []);
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final resized = img.copyResize(decoded, width: _logoWidthDots);
      return _toRasterCommand(resized);
    } catch (e) {
      debugPrint('Logo rasterize failed: $e');
      return null;
    }
  }

  /// Encodes an [image] as an ESC/POS "GS v 0" raster bit image command
  /// (1 bit per pixel, MSB first; a set bit prints as a black dot).
  List<int> _toRasterCommand(img.Image image) {
    final widthBytes = (image.width + 7) ~/ 8;
    final data = <int>[];

    for (var y = 0; y < image.height; y++) {
      final row = List<int>.filled(widthBytes, 0);
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (pixel.luminance < 160) {
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
