import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Generic tabular data for a report export. Headers/rows/totals are plain,
/// already-formatted strings — this same shape works for any report screen,
/// not just the delegate المناطق/الأصناف reports it was built for.
class ReportExportData {
  final String title;
  final String period;
  final List<String> headers;
  final List<List<String>> rows;
  /// Optional bold summary row rendered under the table (same column count
  /// as [headers]); pass null to omit it.
  final List<String>? totals;

  const ReportExportData({
    required this.title,
    required this.period,
    required this.headers,
    required this.rows,
    this.totals,
  });
}

/// Shared PDF/Excel export for any [ReportExportData] — kept out of any one
/// report page so future reports reuse the same rendering instead of each
/// screen rolling its own export logic.
class ReportExporter {
  ReportExporter._();

  static Future<void> exportPdf(
    ReportExportData data, {
    required String companyName,
    String? logoUrl,
  }) async {
    final regularFont = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final logoBytes = await _fetchLogoBytes(logoUrl);
    final generatedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
          margin: const pw.EdgeInsets.all(28),
        ),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(companyName,
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text(data.title, style: const pw.TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                if (logoBytes != null)
                  pw.SizedBox(
                    width: 46,
                    height: 46,
                    child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
                  ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text('الفترة: ${data.period}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Text('تاريخ الإصدار: $generatedAt',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.grey400),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: data.headers,
            data: data.rows,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          if (data.totals != null) ...[
            pw.SizedBox(height: 2),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
                color: PdfColors.blueGrey50,
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: pw.Row(
                children: data.totals!
                    .map((t) => pw.Expanded(
                          child: pw.Text(t,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: '${_fileSafe(data.title)}.pdf');
  }

  static Future<void> exportExcel(
    ReportExportData data, {
    required String companyName,
  }) async {
    final workbook = xls.Excel.createExcel();
    final sheetName = _excelSheetName(data.title);
    final defaultSheetName = workbook.getDefaultSheet();
    if (defaultSheetName != null && defaultSheetName != sheetName) {
      workbook.rename(defaultSheetName, sheetName);
    }
    final sheet = workbook[sheetName];
    sheet.isRTL = true;

    final generatedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    sheet.appendRow([xls.TextCellValue('$companyName — ${data.title}')]);
    sheet.appendRow([xls.TextCellValue('الفترة: ${data.period}')]);
    sheet.appendRow([xls.TextCellValue('تاريخ الإصدار: $generatedAt')]);
    sheet.appendRow(const []);
    sheet.appendRow(data.headers.map((h) => xls.TextCellValue(h)).toList());
    for (final row in data.rows) {
      sheet.appendRow(row.map((c) => xls.TextCellValue(c)).toList());
    }
    if (data.totals != null) {
      sheet.appendRow(data.totals!.map((t) => xls.TextCellValue(t)).toList());
    }

    final bytes = workbook.encode();
    if (bytes == null) return;

    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: '${_fileSafe(data.title)}.xlsx',
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: '$companyName — ${data.title}',
    ));
  }

  /// Fetches the report's logo bytes for PDF embedding — network URL or
  /// inline `data:` URI, mirroring bluetooth_printer.dart's receipt-logo
  /// fetch. Returns null on any failure so a broken/unreachable logo never
  /// blocks the export.
  static Future<Uint8List?> _fetchLogoBytes(String? logoUrl) async {
    if (logoUrl == null || logoUrl.isEmpty) return null;
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
    } catch (_) {
      return null;
    }
  }

  static String _fileSafe(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  /// Excel sheet names are capped at 31 chars and forbid \ / ? * [ ] : —
  /// report titles are short Arabic phrases today but this keeps the export
  /// from silently failing if a longer/odd title is passed in later.
  static String _excelSheetName(String title) {
    final safe = title.replaceAll(RegExp(r'[\\/?*\[\]:]'), '_').trim();
    final name = safe.isEmpty ? 'Report' : safe;
    return name.length > 31 ? name.substring(0, 31) : name;
  }
}
