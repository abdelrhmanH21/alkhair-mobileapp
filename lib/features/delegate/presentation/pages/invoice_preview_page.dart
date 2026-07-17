import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/bluetooth_printer.dart';

/// On-screen "معاينة" of a receipt — no printer connection required. Renders
/// [buildReceiptPlan]'s output (the exact same content/order used to build
/// the real ESC/POS ticket in bluetooth_printer.dart) as a narrow,
/// monospace, paper-styled column, so a delegate/admin can check the
/// receipt's content any time, whether or not a printer is available.
class InvoicePreviewPage extends StatelessWidget {
  final InvoicePrintData data;
  const InvoicePreviewPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade300,
      appBar: AppBar(title: const Text('معاينة الفاتورة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: ReceiptPreviewCard(data: data)),
      ),
    );
  }
}

/// The receipt "paper" itself — extracted as its own widget so it can also
/// be embedded inline (e.g. print_invoice_page.dart could show it above the
/// printer controls) without pulling in a whole Scaffold/page.
class ReceiptPreviewCard extends StatelessWidget {
  final InvoicePrintData data;
  /// ~80mm paper at a legible on-screen density. bluetooth_printer.dart
  /// hard-codes _charsPerLine=42 for both 58mm/80mm printers (no per-printer
  /// paper-width setting is wired into the app yet), so this preview always
  /// mirrors that one fixed layout.
  static const double _paperWidth = 300;

  const ReceiptPreviewCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final elements = buildReceiptPlan(data);
    return Container(
      width: _paperWidth,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: AppTheme.shadowColor, blurRadius: 12, spreadRadius: 1)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Directionality(
        // Physical thermal printers lay bytes out strictly left-to-right on
        // the paper regardless of script — pinning LTR here (rather than
        // inheriting the app's Arabic/RTL default) keeps "left"/"right"
        // alignment in the receipt plan matching the real printed layout.
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: elements.map((e) => _buildElement(context, e)).toList(),
        ),
      ),
    );
  }

  Widget _buildElement(BuildContext context, ReceiptElement element) {
    return switch (element) {
      ReceiptLogoElement(:final logoUrl) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Center(child: _ReceiptLogo(logoUrl: logoUrl)),
        ),
      ReceiptSeparatorLine() => _ReceiptText('-' * 42),
      ReceiptTextLine(:final text, :final bold, :final align) => _ReceiptText(
          text,
          bold: bold,
          textAlign: switch (align) {
            ReceiptAlign.left => TextAlign.left,
            ReceiptAlign.center => TextAlign.center,
            ReceiptAlign.right => TextAlign.right,
          },
        ),
    };
  }
}

class _ReceiptText extends StatelessWidget {
  final String text;
  final bool bold;
  final TextAlign textAlign;
  const _ReceiptText(this.text, {this.bold = false, this.textAlign = TextAlign.left});

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.4,
          color: Colors.black,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      );
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
        height: 40,
        width: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Image.memory(bytes, width: 120, fit: BoxFit.contain, gaplessPlayback: true);
  }
}
