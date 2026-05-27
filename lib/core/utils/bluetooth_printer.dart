import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:intl/intl.dart';

class BluetoothPrinterService {
  static const int _charsPerLine = 42; // standard 80mm ESC/POS columns

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
      final ticket = _buildTicket(data);
      return await PrintBluetoothThermal.writeBytes(ticket);
    } catch (e) {
      debugPrint('Print error: $e');
      return false;
    }
  }

  List<int> _buildTicket(InvoicePrintData d) {
    final List<int> bytes = [];

    void addBytes(List<int> b) => bytes.addAll(b);

    // ESC/POS helper: add text as UTF-8 + LF
    void line(String text) {
      addBytes([...text.codeUnits, 0x0A]);
    }

    void separator() => line('-' * _charsPerLine);

    // ignore: unused_element
    void centeredLine(String text) {
      final padding = ((_charsPerLine - text.length) / 2).floor();
      line(' ' * padding.clamp(0, _charsPerLine) + text);
    }

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

    alignCenter();
    boldOn();
    line('الخير للالبان');
    boldOff();
    line('فاتورة مبيعات ميدانية');
    separator();

    alignLeft();
    line('العميل : ${d.clientName}');
    line('الهاتف : ${d.clientPhone}');
    line('المندوب: ${d.delegateName}');
    line('التاريخ: ${DateFormat('yyyy/MM/dd – HH:mm').format(d.issuedAt)}');
    line('رقم الفاتورة: ${d.invoiceNumber}');
    separator();

    // Header row
    boldOn();
    line(_row('المنتج', 'الكمية', 'السعر', 'الإجمالي'));
    boldOff();
    separator();

    for (final item in d.salesItems) {
      // Wrap long product names onto new lines
      final nameLines = _wrapText(item.productName, 20);
      for (var i = 0; i < nameLines.length; i++) {
        if (i == 0) {
          line(_row(
            nameLines[i],
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
        final nameLines = _wrapText(ret.productName, 20);
        for (var i = 0; i < nameLines.length; i++) {
          if (i == 0) {
            line(_row(
              nameLines[i],
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
    line('إجمالي المبيعات : ${d.grossSales.toStringAsFixed(2)}');
    line('إجمالي المرتجع : ${d.totalReturns.toStringAsFixed(2)}');
    line('الصافي          : ${d.netTotal.toStringAsFixed(2)}');
    separator();
    line('نقداً مستلم     : ${d.cashReceived.toStringAsFixed(2)}');
    line('رصيد مضاف للدين : ${d.balanceAddedToDebt.toStringAsFixed(2)}');
    boldOff();

    separator();
    alignCenter();
    line('شكراً لتعاملكم معنا');
    line('');
    line('');
    line('');

    // Feed and cut: GS V 66 3
    addBytes([0x1D, 0x56, 0x42, 0x03]);

    return bytes;
  }

  /// Fixed-width 4-column row with right-aligned numeric columns.
  String _row(String name, String qty, String price, String total) {
    final n = name.padRight(20).substring(0, 20);
    final q = qty.padLeft(6);
    final p = price.padLeft(8);
    final t = total.padLeft(8);
    return '$n$q$p$t';
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
}

class InvoicePrintData {
  final String invoiceNumber;
  final String clientName;
  final String clientPhone;
  final String delegateName;
  final DateTime issuedAt;
  final List<PrintLineItem> salesItems;
  final List<PrintLineItem> returnedItems;
  final double grossSales;
  final double totalReturns;
  final double netTotal;
  final double cashReceived;
  final double balanceAddedToDebt;

  const InvoicePrintData({
    required this.invoiceNumber,
    required this.clientName,
    required this.clientPhone,
    required this.delegateName,
    required this.issuedAt,
    required this.salesItems,
    required this.returnedItems,
    required this.grossSales,
    required this.totalReturns,
    required this.netTotal,
    required this.cashReceived,
    required this.balanceAddedToDebt,
  });
}

class PrintLineItem {
  final String productName;
  final double quantity;
  final double unitPrice;
  final double subtotal;
  const PrintLineItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });
}
