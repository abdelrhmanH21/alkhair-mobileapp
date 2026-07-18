import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/report_export.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/report_models.dart';

enum _ReportPeriod { month, week, custom }
enum _ReportKind { region, product }

/// تقارير المندوب — بيانات مبيعاته (المناطق/الأصناف) لفترة قابلة للاختيار.
/// مصدر مصدرها الوحيد: DelegateReportController::byRegion()/byProduct()، نفس
/// أسلوب جلب البيانات المستخدم في CommissionBreakdownPage.
class DelegateReportsPage extends StatefulWidget {
  const DelegateReportsPage({super.key});

  @override
  State<DelegateReportsPage> createState() => _DelegateReportsPageState();
}

class _DelegateReportsPageState extends State<DelegateReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  _ReportPeriod _period = _ReportPeriod.month;
  DateTimeRange? _customRange;

  List<RegionReportRowModel>? _regionRows;
  List<ProductReportRowModel>? _productRows;

  // This page lives forever behind DashboardSection's card (and every other
  // tab in DelegateHomePage's IndexedStack), all sharing one DelegateBloc.
  // Tracks this page's own two outstanding fetches by requestId so an
  // unrelated DelegateFailure elsewhere can never surface here.
  final _tracker = RequestTracker<_ReportKind>();

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _fetchReports() {
    final params = _currentParams();
    final regionEvent = DelegateReportByRegionRequested(
      period: params.period,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    final productEvent = DelegateReportByProductRequested(
      period: params.period,
      dateFrom: params.dateFrom,
      dateTo: params.dateTo,
    );
    _tracker.start(regionEvent.requestId, _ReportKind.region);
    _tracker.start(productEvent.requestId, _ReportKind.product);
    context.read<DelegateBloc>().add(regionEvent);
    context.read<DelegateBloc>().add(productEvent);
  }

  /// Human-readable period label for the export header — mirrors
  /// _currentParams()'s period resolution but as display text rather than
  /// API query params.
  String get _periodLabel {
    switch (_period) {
      case _ReportPeriod.week:
        return 'هذا الأسبوع';
      case _ReportPeriod.month:
        return 'هذا الشهر';
      case _ReportPeriod.custom:
        final range = _customRange;
        if (range == null) return 'هذا الشهر';
        final fmt = DateFormat('yyyy-MM-dd');
        return '${fmt.format(range.start)} — ${fmt.format(range.end)}';
    }
  }

  ({String? period, String? dateFrom, String? dateTo}) _currentParams() {
    switch (_period) {
      case _ReportPeriod.week:
        return (period: 'week', dateFrom: null, dateTo: null);
      case _ReportPeriod.month:
        return (period: 'month', dateFrom: null, dateTo: null);
      case _ReportPeriod.custom:
        final range = _customRange;
        if (range == null) return (period: 'month', dateFrom: null, dateTo: null);
        final fmt = DateFormat('yyyy-MM-dd');
        return (period: null, dateFrom: fmt.format(range.start), dateTo: fmt.format(range.end));
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (range != null) {
      setState(() {
        _period = _ReportPeriod.custom;
        _customRange = range;
        _regionRows = null;
        _productRows = null;
      });
      _fetchReports();
    }
  }

  void _selectPeriod(_ReportPeriod period) {
    if (period == _ReportPeriod.custom) {
      _pickCustomRange();
      return;
    }
    setState(() {
      _period = period;
      _regionRows = null;
      _productRows = null;
    });
    _fetchReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'تقرير المناطق'),
            Tab(text: 'تقرير الأصناف'),
          ],
        ),
      ),
      body: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateReportByRegionLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _regionRows = state.rows);
          } else if (state is DelegateReportByProductLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _productRows = state.rows);
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            AppSnackbar.showError(ctx, state.message);
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('هذا الشهر'),
                      selected: _period == _ReportPeriod.month,
                      onSelected: (_) => _selectPeriod(_ReportPeriod.month),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('هذا الأسبوع'),
                      selected: _period == _ReportPeriod.week,
                      onSelected: (_) => _selectPeriod(_ReportPeriod.week),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(_period == _ReportPeriod.custom && _customRange != null
                          ? '${DateFormat('MM-dd').format(_customRange!.start)}..${DateFormat('MM-dd').format(_customRange!.end)}'
                          : 'نطاق مخصص'),
                      selected: _period == _ReportPeriod.custom,
                      onSelected: (_) => _selectPeriod(_ReportPeriod.custom),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RegionReportView(rows: _regionRows, periodLabel: _periodLabel),
                  _ProductReportView(rows: _productRows, periodLabel: _periodLabel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegionReportView extends StatelessWidget {
  final List<RegionReportRowModel>? rows;
  final String periodLabel;
  const _RegionReportView({required this.rows, required this.periodLabel});

  ReportExportData _exportData() {
    final r = rows ?? [];
    final totalCustomers = r.fold(0, (s, row) => s + row.customerCount);
    final totalSales = r.fold(0.0, (s, row) => s + row.totalSales);
    return ReportExportData(
      title: 'تقرير المناطق',
      period: periodLabel,
      headers: const ['المنطقة', 'عدد العملاء', 'المبيعات', 'نسبة المشاركة %', 'متوسط العميل'],
      rows: r
          .map((row) => [
                row.regionName,
                '${row.customerCount}',
                row.totalSales.toStringAsFixed(2),
                '${row.participationPct.toStringAsFixed(1)}%',
                row.avgPerCustomer.toStringAsFixed(2),
              ])
          .toList(),
      totals: ['الإجمالي', '$totalCustomers', totalSales.toStringAsFixed(2), '-', '-'],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد مبيعات في هذه الفترة.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows!.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _ExportButtonsRow(buildData: _exportData);
        }
        final r = rows![i - 1];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(r.regionName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Text('${r.participationPct.toStringAsFixed(1)}%',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ReportMiniStat(label: 'عدد العملاء', value: '${r.customerCount}'),
                    _ReportMiniStat(label: 'المبيعات', value: r.totalSales.toStringAsFixed(2)),
                    _ReportMiniStat(label: 'متوسط العميل', value: r.avgPerCustomer.toStringAsFixed(2)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductReportView extends StatelessWidget {
  final List<ProductReportRowModel>? rows;
  final String periodLabel;
  const _ProductReportView({required this.rows, required this.periodLabel});

  ReportExportData _exportData() {
    final p = rows ?? [];
    final totalQty = p.fold(0.0, (s, row) => s + row.totalQuantitySold);
    final totalValue = p.fold(0.0, (s, row) => s + row.totalValue);
    return ReportExportData(
      title: 'تقرير الأصناف',
      period: periodLabel,
      headers: const ['المنتج', 'الوحدة', 'الكمية المباعة', 'القيمة الإجمالية'],
      rows: p
          .map((row) => [
                row.productName,
                row.unit,
                row.totalQuantitySold.toStringAsFixed(2),
                row.totalValue.toStringAsFixed(2),
              ])
          .toList(),
      totals: ['الإجمالي', '-', totalQty.toStringAsFixed(2), totalValue.toStringAsFixed(2)],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows!.isEmpty) {
      return const Center(
          child: Text('لا توجد مبيعات في هذه الفترة.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows!.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _ExportButtonsRow(buildData: _exportData);
        }
        final p = rows![i - 1];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
            title: Text(p.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${p.totalQuantitySold.toStringAsFixed(2)} ${p.unit}'),
            trailing: Text(p.totalValue.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
          ),
        );
      },
    );
  }
}

// ─── Export buttons row (shared by both report tabs) ──────────────────────────

class _ExportButtonsRow extends StatefulWidget {
  final ReportExportData Function() buildData;
  const _ExportButtonsRow({required this.buildData});

  @override
  State<_ExportButtonsRow> createState() => _ExportButtonsRowState();
}

class _ExportButtonsRowState extends State<_ExportButtonsRow> {
  bool _exportingPdf = false;
  bool _exportingExcel = false;

  String get _companyName {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.companyName : '';
  }

  String? get _logoUrl {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? (state.config.logoColorUrl ?? state.config.logoUrl) : null;
  }

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      await ReportExporter.exportPdf(widget.buildData(), companyName: _companyName, logoUrl: _logoUrl);
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء ملف PDF. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exportingExcel = true);
    try {
      await ReportExporter.exportExcel(widget.buildData(), companyName: _companyName);
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء ملف Excel. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportingPdf ? null : _exportPdf,
                icon: _exportingPdf
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('تصدير PDF'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exportingExcel ? null : _exportExcel,
                icon: _exportingExcel
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('تصدير Excel'),
              ),
            ),
          ],
        ),
      );
}

class _ReportMiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _ReportMiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
}
