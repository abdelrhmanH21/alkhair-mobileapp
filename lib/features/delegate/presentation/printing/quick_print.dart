import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../../core/utils/printer_manager.dart';
import '../../../app_config/data/models/app_config_model.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../pages/print_invoice_page.dart';

/// The one mapping from a delegate invoice JSON + app config to what gets
/// printed — shared by the print screen and the one-tap flow so both always
/// print the same receipt.
InvoicePrintData delegateInvoicePrintData(Map<String, dynamic> invoice, AppConfigModel? config) =>
    InvoicePrintData.fromInvoiceJson(
      invoice,
      showPhone: config?.showPhone ?? true,
      companyName: config?.companyName ?? '',
      headerText: config?.headerText,
      footerText: config?.footerText,
      logoUrl: config?.logoUrl,
      paperWidth: config?.paperWidth ?? '80mm',
    );

/// Fetches invoice [invoiceId] and builds its print data. [configBloc] is
/// captured by the caller before any await (no BuildContext across gaps).
Future<InvoicePrintData> loadDelegateInvoicePrintData(AppConfigBloc configBloc, int invoiceId) async {
  final res = await sl<ApiClient>().dio.get('${ApiEndpoints.delegateInvoices}/$invoiceId');
  final invoice = res.data['data'] as Map<String, dynamic>;
  final config = await configBloc.ensureLoaded();
  return delegateInvoicePrintData(invoice, config);
}

/// "طباعة" with the saved printer in one tap; if no printer is saved yet,
/// opens the print screen once so the user can pick one (it is remembered
/// from then on). Never blocks the UI — progress/result show in
/// [PrintJobStatusBar].
Future<void> quickPrintInvoice(BuildContext context, int invoiceId) async {
  final manager = sl<PrinterManager>();
  if (!manager.hasSavedPrinter) {
    await openPrinterPicker(context, invoiceId);
    return;
  }
  final configBloc = context.read<AppConfigBloc>();
  await manager.printInvoice(invoiceId, () => loadDelegateInvoicePrintData(configBloc, invoiceId));
}

Future<void> openPrinterPicker(BuildContext context, int invoiceId) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PrintInvoicePage(invoiceId: invoiceId)),
    );

/// Inline, non-blocking status of the latest one-tap print: "جاري
/// الطباعة…", "تمت الطباعة", or the failure with "إعادة الطباعة" and
/// "اختيار طابعة". Shows nothing when there's no job (or it belongs to a
/// different invoice than [invoiceId], when given).
class PrintJobStatusBar extends StatelessWidget {
  final int? invoiceId;
  const PrintJobStatusBar({super.key, this.invoiceId});

  @override
  Widget build(BuildContext context) {
    if (!sl.isRegistered<PrinterManager>()) return const SizedBox.shrink();
    final manager = sl<PrinterManager>();
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final job = manager.lastJob;
        if (job == null || (invoiceId != null && job.invoiceId != invoiceId)) {
          return const SizedBox.shrink();
        }
        switch (job.status) {
          case PrintJobStatus.printing:
            return _bar(
              key: const Key('print-status-printing'),
              color: AppTheme.primary,
              leading: const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              text: 'جاري الطباعة…',
            );
          case PrintJobStatus.success:
            return _bar(
              key: const Key('print-status-success'),
              color: AppTheme.secondary,
              leading: const Icon(Icons.check_circle_rounded, color: AppTheme.secondary, size: 20),
              text: job.message ?? 'تمت الطباعة',
              actions: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'إغلاق',
                  onPressed: manager.clearLastJob,
                ),
              ],
            );
          case PrintJobStatus.failed:
            return _bar(
              key: const Key('print-status-failed'),
              color: AppTheme.danger,
              leading: const Icon(Icons.print_disabled_outlined, color: AppTheme.danger, size: 20),
              text: '${job.message ?? 'فشل الطباعة'} — الفاتورة محفوظة.',
              actions: [
                TextButton(onPressed: manager.retryLast, child: const Text('إعادة الطباعة')),
                TextButton(
                  onPressed: () => openPrinterPicker(context, job.invoiceId),
                  child: const Text('اختيار طابعة'),
                ),
              ],
            );
        }
      },
    );
  }

  Widget _bar({
    required Key key,
    required Color color,
    required Widget leading,
    required String text,
    List<Widget> actions = const [],
  }) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            leading,
            Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ...actions,
          ],
        ),
      );
}
