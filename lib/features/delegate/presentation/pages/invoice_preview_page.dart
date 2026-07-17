import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/bluetooth_printer.dart';

/// On-screen "معاينة" of a receipt — no printer connection required. Renders
/// [buildReceiptPlan]'s output (the exact same content/order used to build
/// the real ESC/POS ticket in bluetooth_printer.dart) as a polished,
/// right-aligned RTL card, so a delegate/admin can check the receipt's
/// content any time, whether or not a printer is available.
///
/// This is a *visual* rendering of buildReceiptPlan()'s data only — it does
/// not change what content appears or under what conditions (that logic
/// lives solely in buildReceiptPlan()). The one exception is the items
/// table: buildReceiptPlan() bakes item rows into fixed-width padded
/// strings for the physical printer's monospace columns, which can't be
/// split back into clean table cells without fragile string-parsing. Since
/// ReceiptPreviewCard already receives the full [InvoicePrintData] (the
/// same object buildReceiptPlan() itself was built from), the items table
/// renders straight from data.salesItems/data.returnedItems instead —
/// still the one shared data source, just read as structured fields rather
/// than re-parsed from printer-formatted text.
class InvoicePreviewPage extends StatelessWidget {
  final InvoicePrintData data;
  const InvoicePreviewPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(title: const Text('معاينة الفاتورة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Center(child: ReceiptPreviewCard(data: data)),
      ),
    );
  }
}

/// The receipt card itself — extracted as its own widget so it can also be
/// embedded inline (e.g. print_invoice_page.dart could show it above the
/// printer controls) without pulling in a whole Scaffold/page.
class ReceiptPreviewCard extends StatelessWidget {
  final InvoicePrintData data;
  static const double _cardWidth = 340;

  const ReceiptPreviewCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final elements = buildReceiptPlan(data);
    final children = <Widget>[];

    var i = 0;
    while (i < elements.length) {
      final el = elements[i];

      // The items-table header is a fixed marker string ("الصنف" padded to
      // printer columns) — once we see it, render our own table from
      // data.salesItems/returnedItems and skip every raw printer-formatted
      // line buildReceiptPlan() emitted for the items/returns block, up to
      // (not including) the totals block's first line.
      if (el is ReceiptTextLine && el.text.trimLeft().startsWith('الصنف')) {
        children.add(_ItemsSection(data: data));
        i++;
        while (i < elements.length) {
          final next = elements[i];
          if (next is ReceiptTextLine && next.text.startsWith('إجمالي المبيعات:')) break;
          i++;
        }
        continue;
      }

      children.add(_buildElement(el));
      i++;
    }

    return Container(
      width: _cardWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: AppTheme.shadowColor, blurRadius: 16, spreadRadius: 1)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Directionality(
        // A polished on-screen card should read like the rest of the
        // Arabic app — right-to-left — rather than mimicking the physical
        // printer's strict left-to-right byte order (that fidelity still
        // lives in bluetooth_printer.dart's own ESC/POS output, untouched).
        textDirection: TextDirection.rtl,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _buildElement(ReceiptElement element) {
    return switch (element) {
      ReceiptLogoElement(:final logoUrl) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Center(child: _ReceiptLogo(logoUrl: logoUrl)),
        ),
      ReceiptSeparatorLine() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
        ),
      ReceiptTextLine(:final text, :final bold, :final align) => _ReceiptLine(text, bold: bold, align: align),
    };
  }
}

/// One general (non-item-table) receipt line. Alignment mirrors the
/// left/center/right split buildReceiptPlan() carries, but re-expressed for
/// a right-aligned RTL card rather than an LTR paper column: centered lines
/// (logo caption / header / footer / company name) stay centered, every
/// other line — general info and the totals block alike — reads naturally
/// right-aligned. The bold company-name line gets a larger "title" size;
/// "الصافي المستحق" (the invoice's own final total) is called out in the
/// app's primary color, matching how invoice_detail_page.dart emphasizes
/// its own net-total row.
class _ReceiptLine extends StatelessWidget {
  final String text;
  final bool bold;
  final ReceiptAlign align;
  const _ReceiptLine(this.text, {required this.bold, required this.align});

  @override
  Widget build(BuildContext context) {
    final isHero = text.startsWith('الصافي المستحق:');
    final isCentered = align == ReceiptAlign.center;

    double fontSize = 13;
    Color color = Colors.black87;
    FontWeight weight = bold ? FontWeight.bold : FontWeight.normal;

    if (isCentered && bold) {
      // Company name — the card's title.
      fontSize = 17;
    } else if (isCentered) {
      // Header/footer welcome text.
      fontSize = 12;
      color = Colors.grey.shade600;
    } else if (isHero) {
      fontSize = 16;
      color = AppTheme.primary;
    } else if (bold) {
      // Rest of the totals block.
      fontSize = 13.5;
    } else {
      color = Colors.black87.withValues(alpha: 0.85);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        textAlign: isCentered ? TextAlign.center : TextAlign.right,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color, height: 1.5),
      ),
    );
  }
}

/// Sales items table, and — only when the invoice has any — a "المرتجعات"
/// sub-section with its own table, exactly mirroring buildReceiptPlan()'s
/// own `if (d.returnedItems.isNotEmpty)` condition (same field, same
/// invoice, no new logic).
class _ItemsSection extends StatelessWidget {
  final InvoicePrintData data;
  const _ItemsSection({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ItemsTable(items: data.salesItems),
        if (data.returnedItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('المرتجعات',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.danger)),
          ),
          _ItemsTable(items: data.returnedItems, isReturns: true),
        ],
      ],
    );
  }
}

/// A real, right-aligned RTL table — الصنف | الوحدة | الكمية | السعر |
/// الإجمالي — with the name column given enough flex to wrap long product
/// names cleanly within its own column, never disturbing the numeric
/// columns' alignment (unlike the printer's crude 12-char mid-word chunking
/// in bluetooth_printer.dart, which stays untouched for the physical ticket).
class _ItemsTable extends StatelessWidget {
  final List<PrintLineItem> items;
  final bool isReturns;
  const _ItemsTable({required this.items, this.isReturns = false});

  static const Map<int, TableColumnWidth> _columnWidths = {
    0: FlexColumnWidth(3.2), // الصنف
    1: FlexColumnWidth(1.1), // الوحدة
    2: FlexColumnWidth(1.1), // الكمية
    3: FlexColumnWidth(1.4), // السعر
    4: FlexColumnWidth(1.6), // الإجمالي
  };

  @override
  Widget build(BuildContext context) {
    final headerStyle = TextStyle(
        fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.grey.shade600, letterSpacing: 0.2);
    final totalColor = isReturns ? AppTheme.danger : AppTheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: _columnWidths,
          children: [
            TableRow(children: [
              _cell('الصنف', headerStyle, align: TextAlign.right),
              _cell('الوحدة', headerStyle),
              _cell('الكمية', headerStyle),
              _cell('السعر', headerStyle),
              _cell('الإجمالي', headerStyle),
            ]),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
        ),
        Table(
          columnWidths: _columnWidths,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final item in items)
              TableRow(children: [
                _cell(
                  item.productName,
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black87),
                  align: TextAlign.right,
                  wrap: true,
                ),
                _cell(item.unit, TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                _cell(
                  isReturns ? '-${item.quantity.toStringAsFixed(2)}' : item.quantity.toStringAsFixed(2),
                  TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                _cell(item.unitPrice.toStringAsFixed(2), TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                _cell(item.subtotal.toStringAsFixed(2),
                    TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: totalColor)),
              ]),
          ],
        ),
      ],
    );
  }

  Widget _cell(String text, TextStyle style, {TextAlign align = TextAlign.center, bool wrap = false}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        child: Text(
          text,
          textAlign: align,
          softWrap: wrap,
          overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

/// Fetches the logo via the same fetch→resize→1-bit-threshold pipeline the
/// real printer uses (BluetoothPrinterService.renderLogoPreviewPng), so the
/// preview shows the actual monochrome bitmap that would print, not the
/// original color logo.
class _ReceiptLogo extends StatefulWidget {
  final String logoUrl;
  const _ReceiptLogo({required this.logoUrl});

  @override
  State<_ReceiptLogo> createState() => _ReceiptLogoState();
}

class _ReceiptLogoState extends State<_ReceiptLogo> {
  final _printer = sl<BluetoothPrinterService>();
  Uint8List? _pngBytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await _printer.renderLogoPreviewPng(widget.logoUrl);
    if (!mounted) return;
    setState(() {
      _pngBytes = bytes;
      _failed = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final bytes = _pngBytes;
    if (bytes == null) {
      return const SizedBox(
        height: 44,
        width: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(bytes, width: 110, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}
