import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/report_export.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// رقم الباتش (printed on the pack) shown large with a copy button, one
/// copy-ready coding-machine line per output, and the batch-card PDF
/// action — the mobile twin of the web BatchNumberPanel (BatchCard.tsx).
/// Shown right after بدء تشغيلة and in استلام إنتاج تام's run picker.
class BatchNumberPanel extends StatelessWidget {
  final int batchId;
  final String? batchNumber;
  final String? runNumber;
  final List<ProductionCodingLineModel> codingLines;
  final AdminRemoteDataSource remote;

  const BatchNumberPanel({
    super.key,
    required this.batchId,
    required this.batchNumber,
    required this.runNumber,
    required this.codingLines,
    required this.remote,
  });

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) AppSnackbar.showSuccess(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final number = batchNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('رقم الباتش (يُطبع على العبوة)', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        Row(
          children: [
            Expanded(
              child: Text(
                batchNumberLabel(number),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
            ),
            if (number != null)
              IconButton(
                tooltip: 'نسخ رقم الباتش',
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, number, 'تم نسخ رقم الباتش'),
              ),
          ],
        ),
        if (runNumber != null)
          Text('رقم التشغيلة: $runNumber', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        if (codingLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('سطر ماكينة التكويد', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ...codingLines.map((c) => Row(
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        codingLines.length > 1 && c.productName != null ? '${c.line}\n${c.productName}' : c.line,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'نسخ سطر التكويد',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copy(context, c.line, 'تم نسخ سطر التكويد'),
                  ),
                ],
              )),
        ],
        const SizedBox(height: 6),
        _BatchCardPdfButton(batchId: batchId, remote: remote),
      ],
    );
  }
}

class _BatchCardPdfButton extends StatefulWidget {
  final int batchId;
  final AdminRemoteDataSource remote;
  const _BatchCardPdfButton({required this.batchId, required this.remote});

  @override
  State<_BatchCardPdfButton> createState() => _BatchCardPdfButtonState();
}

class _BatchCardPdfButtonState extends State<_BatchCardPdfButton> {
  bool _busy = false;

  Future<void> _export() async {
    final config = context.read<AppConfigBloc>().state;
    final companyName = config is AppConfigLoaded ? config.config.companyName : '';
    // Monochrome receipt logo first — this card is printed black & white.
    final logoUrl = config is AppConfigLoaded ? (config.config.logoUrl ?? config.config.logoColorUrl) : null;
    setState(() => _busy = true);
    try {
      final detail = await widget.remote.fetchBatchDetail(widget.batchId);
      await ReportExporter.exportBatchCardPdf(batchCardExportData(detail),
          companyName: companyName, logoUrl: logoUrl);
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء بطاقة التشغيلة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: const Text('بطاقة التشغيلة (PDF)'),
      );
}

String _fmtQty(double v) => NumberFormat('#,##0.##').format(v);

String _fmtDate(String? ymd) {
  if (ymd == null) return '—';
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('dd/MM/yyyy').format(d);
}

/// Batch-card payload from GET /manufacturing/{id} — top-level so the card's
/// content is unit-testable without rendering a PDF.
BatchCardExportData batchCardExportData(ProductionBatchDetailModel d) {
  String lineFor(int outputId) =>
      d.codingLines.where((c) => c.outputId == outputId).map((c) => c.line).firstOrNull ?? '—';
  final issued = d.materials.where((m) => m.itemType != 'packaging').toList();
  final packaging = d.materials.where((m) => m.itemType == 'packaging').toList();
  List<List<String>> rows(List<ProductionMaterialModel> list) => [
        for (var i = 0; i < list.length; i++)
          [
            '${i + 1}',
            '${list[i].materialName ?? '—'}${list[i].isReentry ? ' (إعادة تشغيل)' : ''}',
            _fmtQty(list[i].actualQuantityUsed ?? list[i].quantityUsed),
            list[i].unit ?? '',
          ],
      ];

  return BatchCardExportData(
    batchNumber: batchNumberLabel(d.batchNumber),
    meta: [
      ['رقم التشغيلة', d.runNumber ?? '#${d.id}'],
      ['تاريخ الإنتاج', _fmtDate(d.productionDate)],
      ['الوصفة', [d.categoryName, d.recipeName].whereType<String>().join(' — ').ifEmpty('—')],
      ['المعمل', d.labName ?? '—'],
      ['بواسطة', d.createdByName ?? '—'],
      ['تاريخ الفتح', d.startedAt == null ? '—' : DateFormat('dd/MM/yyyy').format(d.startedAt!)],
    ],
    outputRows: d.outputs
        .map((o) => [
              '${o.productName}${o.isByproduct ? ' (ثانوي)' : ''}',
              _fmtDate(o.expiryDate),
              o.actualQuantity == null ? '—' : '${_fmtQty(o.actualQuantity!)} ${o.unit}',
              lineFor(o.id),
            ])
        .toList(),
    materialRows: rows(issued),
    packagingRows: rows(packaging),
    notes: d.notes,
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
