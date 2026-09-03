import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/report_export.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "ملخص اليوم" (يومية مبيعات) — the full paper-form-shaped daily summary
/// for one settled shift, reachable from AdminSettlementHistoryPage. Same
/// data as the web's DailySummaryModal, laid out as a scrollable in-app
/// view instead of a print-CSS page. Export reuses ReportExporter (the
/// shared PDF-export helper already built for the delegate reports
/// feature) via its new exportDailySummaryPdf() method — see that file's
/// doc comment.
class DailySummaryPage extends StatefulWidget {
  final int settlementId;
  const DailySummaryPage({super.key, required this.settlementId});

  @override
  State<DailySummaryPage> createState() => _DailySummaryPageState();
}

class _DailySummaryPageState extends State<DailySummaryPage> {
  final _remote = sl<AdminRemoteDataSource>();

  DailySummaryModel? _data;
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _remote.fetchDailySummary(widget.settlementId);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'فشل تحميل ملخص اليوم.'; });
    }
  }

  String get _companyName {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.companyName : '';
  }

  String? get _logoUrl {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? (state.config.logoColorUrl ?? state.config.logoUrl) : null;
  }

  Future<void> _exportPdf() async {
    final d = _data;
    if (d == null) return;
    setState(() => _exporting = true);
    try {
      final money = NumberFormat('#,##0.00');
      final dateFmt = DateFormat('yyyy-MM-dd');
      final export = DailySummaryExportData(
        title: 'ملخص اليوم',
        subtitle: 'المندوب: ${d.delegateName} — تحميلة #${d.loadingId}',
        dateLabel: dateFmt.format(d.loadedAt ?? d.settledAt),
        isBackfilled: d.isBackfilled,
        productHeaders: const ['اسم الصنف', 'الوحدة', 'منصرف', 'مباع', 'سعر البيع', 'الإجمالي بالنقدي', 'رصيد السيارة'],
        productRows: d.products
            .map((p) => [
                  p.name,
                  p.unit,
                  p.issuedQty.toStringAsFixed(2),
                  p.soldQty.toStringAsFixed(2),
                  money.format(p.unitPrice),
                  money.format(p.cashTotal),
                  p.remainingTruckStock.toStringAsFixed(2),
                ])
            .toList(),
        cashRows: [
          ['إجمالي المبيعات (فاتورة)', money.format(d.summary.grossSalesTotal)],
          ['المبيعات (نقدي محصل)', d.summary.grossSales != null ? money.format(d.summary.grossSales) : 'غير معروف'],
          ['التحصيلات', d.summary.totalCollections != null ? money.format(d.summary.totalCollections) : 'غير معروف'],
          ['المصروفات', d.summary.totalExpenses != null ? money.format(d.summary.totalExpenses) : 'غير معروف'],
          ['المرتجعات', money.format(d.summary.totalReturns)],
          ['الأجل', money.format(d.summary.totalDebtAdded)],
          ['الكاش', money.format(d.summary.expectedCash)],
          ['المحفظة', money.format(d.summary.walletAmount)],
          ['الفرق', money.format(d.summary.cashVariance)],
          ['إجمالي المبيعات بسعر الكتالوج', money.format(d.summary.catalogSalesTotal)],
          ['إجمالي الفروقات', money.format(d.summary.totalVariances)],
        ],
        collectionsHeaders: const ['العميل', 'المبلغ'],
        collectionsRows: d.collections.map((c) => [c.customer, money.format(c.amount)]).toList(),
        debtHeaders: const ['العميل', 'المبلغ'],
        debtRows: d.debtInvoices.map((i) => [i.customer, money.format(i.amount)]).toList(),
        returnsHeaders: const ['العميل', 'الصنف', 'الكمية', 'المبلغ', 'طريقة الاسترجاع'],
        returnsRows: d.returns
            .map((r) => [
                  r.customer,
                  r.product,
                  r.quantity.toStringAsFixed(2),
                  money.format(r.value),
                  r.refundMethod == 'in_kind_replacement' && r.replacement != null
                      ? 'بدل عيني: ${r.replacement!.productName} ×${r.replacement!.quantity.toStringAsFixed(2)}'
                      : 'كاش',
                ])
            .toList(),
        expensesHeaders: const ['البيان', 'المبلغ'],
        expensesRows: d.expenses.map((e) => [e.description, money.format(e.amount)]).toList(),
        variancesHeaders: const ['العميل', 'الصنف', 'الكمية', 'سعر الكتالوج', 'السعر المحصل', 'الفرق'],
        variancesRows: d.variances
            .map((v) => [
                  v.customer,
                  v.product,
                  v.quantity.toStringAsFixed(2),
                  money.format(v.catalogPrice),
                  money.format(v.chargedPrice),
                  money.format(v.variance),
                ])
            .toList(),
      );
      await ReportExporter.exportDailySummaryPdf(export, companyName: _companyName, logoUrl: _logoUrl);
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء ملف PDF. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ملخص اليوم'),
        actions: [
          if (_data != null)
            IconButton(
              onPressed: _exporting ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'تصدير PDF',
            ),
        ],
      ),
      body: _build(),
    );
  }

  Widget _build() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    final d = _data;
    if (d == null) return const SizedBox.shrink();

    final dateFmt = DateFormat('yyyy-MM-dd');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text('المندوب: ${d.delegateName} — تحميلة #${d.loadingId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text('التاريخ: ${dateFmt.format(d.loadedAt ?? d.settledAt)}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          if (d.isBackfilled) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, size: 13, color: Colors.amber),
              const SizedBox(width: 4),
              Text('بيانات تاريخية غير مكتملة',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade800)),
            ]),
          ],

          const SizedBox(height: 14),
          _CashSummaryCard(summary: d.summary),

          const SizedBox(height: 16),
          const _SectionHeader('الأصناف'),
          _ProductsTable(products: d.products),

          const SizedBox(height: 16),
          const _SectionHeader('التحصيلات'),
          _SimpleDetailTable(
            headers: const ['العميل', 'المبلغ'],
            rows: d.collections.map((c) => [c.customer, c.amount.toStringAsFixed(2)]).toList(),
          ),

          const SizedBox(height: 16),
          const _SectionHeader('الأجل'),
          _SimpleDetailTable(
            headers: const ['العميل', 'المبلغ'],
            rows: d.debtInvoices.map((i) => [i.customer, i.amount.toStringAsFixed(2)]).toList(),
          ),

          const SizedBox(height: 16),
          const _SectionHeader('المرتجعات'),
          _ReturnsTable(returns: d.returns),

          const SizedBox(height: 16),
          const _SectionHeader('المصروفات'),
          _SimpleDetailTable(
            headers: const ['البيان', 'المبلغ'],
            rows: d.expenses.map((e) => [e.description, e.amount.toStringAsFixed(2)]).toList(),
          ),

          const SizedBox(height: 16),
          const _SectionHeader('الفروقات'),
          _SimpleDetailTable(
            headers: const ['العميل', 'الصنف', 'الكمية', 'سعر الكتالوج', 'السعر المحصل', 'الفرق'],
            rows: d.variances
                .map((v) => [
                      v.customer,
                      v.product,
                      v.quantity.toStringAsFixed(2),
                      v.catalogPrice.toStringAsFixed(2),
                      v.chargedPrice.toStringAsFixed(2),
                      v.variance.toStringAsFixed(2),
                    ])
                .toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );
}

class _CashSummaryCard extends StatelessWidget {
  final DailySummaryCashRowModel summary;
  const _CashSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final varianceColor = summary.cashVariance == 0
        ? AppTheme.textMuted
        : summary.cashVariance > 0
            ? AppTheme.secondary
            : AppTheme.danger;

    final variancesColor = summary.totalVariances == 0
        ? AppTheme.textMuted
        : summary.totalVariances > 0
            ? AppTheme.secondary
            : AppTheme.danger;

    final rows = <(String, String, Color)>[
      ('إجمالي المبيعات (فاتورة)', summary.grossSalesTotal.toStringAsFixed(2), AppTheme.primary),
      ('المبيعات (نقدي محصل)', summary.grossSales?.toStringAsFixed(2) ?? 'غير معروف', AppTheme.primary),
      ('التحصيلات', summary.totalCollections?.toStringAsFixed(2) ?? 'غير معروف', AppTheme.primary),
      ('المصروفات', summary.totalExpenses?.toStringAsFixed(2) ?? 'غير معروف', AppTheme.danger),
      ('المرتجعات', summary.totalReturns.toStringAsFixed(2), AppTheme.danger),
      ('الأجل', summary.totalDebtAdded.toStringAsFixed(2), AppTheme.accent),
      ('الكاش', summary.expectedCash.toStringAsFixed(2), AppTheme.secondary),
      ('المحفظة', summary.walletAmount.toStringAsFixed(2), AppTheme.accent),
      ('الفرق', summary.cashVariance.toStringAsFixed(2), varianceColor),
      // Reference-only pair: catalogSalesTotal/totalVariances never feed
      // into expectedCash's own formula — see AdminDelegateController
      // ::dailySummary()'s doc comment.
      ('إجمالي المبيعات بسعر الكتالوج', summary.catalogSalesTotal.toStringAsFixed(2), AppTheme.textMuted),
      ('إجمالي الفروقات', summary.totalVariances.toStringAsFixed(2), variancesColor),
    ];

    return Card(
      color: AppTheme.cardBg,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          runSpacing: 8,
          spacing: 8,
          children: rows
              .map((r) => SizedBox(
                    width: (MediaQuery.of(context).size.width - 48) / 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: r.$3.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$1, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          Text(r.$2, style: TextStyle(fontWeight: FontWeight.bold, color: r.$3, fontSize: 14)),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  final List<DailySummaryProductModel> products;
  const _ProductsTable({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Text('لا توجد أصناف في هذه التحميلة.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowHeight: 36,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 40,
        columns: const [
          DataColumn(label: Text('اسم الصنف')),
          DataColumn(label: Text('الوحدة')),
          DataColumn(label: Text('منصرف')),
          DataColumn(label: Text('مباع')),
          DataColumn(label: Text('سعر البيع')),
          DataColumn(label: Text('الإجمالي')),
          DataColumn(label: Text('رصيد السيارة')),
        ],
        rows: products
            .map((p) => DataRow(cells: [
                  DataCell(Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(p.unit)),
                  DataCell(Text(p.issuedQty.toStringAsFixed(2))),
                  DataCell(Text(p.soldQty.toStringAsFixed(2))),
                  DataCell(Text(p.unitPrice.toStringAsFixed(2))),
                  DataCell(Text(p.cashTotal.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary))),
                  DataCell(Text(p.remainingTruckStock.toStringAsFixed(2))),
                ]))
            .toList(),
      ),
    );
  }
}

class _SimpleDetailTable extends StatelessWidget {
  final List<String> headers;
  final List<List<String>> rows;
  const _SimpleDetailTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('لا يوجد', style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 34,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 38,
        columns: headers.map((h) => DataColumn(label: Text(h))).toList(),
        rows: rows
            .map((r) => DataRow(cells: r.map((c) => DataCell(Text(c))).toList()))
            .toList(),
      ),
    );
  }
}

class _ReturnsTable extends StatelessWidget {
  final List<DailySummaryReturnModel> returns;
  const _ReturnsTable({required this.returns});

  @override
  Widget build(BuildContext context) {
    if (returns.isEmpty) {
      return const Text('لا يوجد', style: TextStyle(color: AppTheme.textMuted, fontSize: 12));
    }
    return Column(
      children: returns
          .map((r) => Card(
                color: AppTheme.cardBg,
                surfaceTintColor: Colors.transparent,
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text('${r.customer} — ${r.product}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          Text(r.value.toStringAsFixed(2),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('الكمية: ${r.quantity.toStringAsFixed(2)} ${r.unit} — الحالة: ${r.condition}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      if (r.refundMethod == 'in_kind_replacement' && r.replacement != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '← بدل عيني: ${r.replacement!.productName} ×${r.replacement!.quantity.toStringAsFixed(2)} = ${r.replacement!.value.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text('كاش', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}
