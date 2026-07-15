import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/report_models.dart';

enum _ReportPeriod { month, week, custom }

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
    context.read<DelegateBloc>().add(DelegateReportByRegionRequested(
          period: params.period,
          dateFrom: params.dateFrom,
          dateTo: params.dateTo,
        ));
    context.read<DelegateBloc>().add(DelegateReportByProductRequested(
          period: params.period,
          dateFrom: params.dateFrom,
          dateTo: params.dateTo,
        ));
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
            setState(() => _regionRows = state.rows);
          } else if (state is DelegateReportByProductLoaded) {
            setState(() => _productRows = state.rows);
          } else if (state is DelegateFailure) {
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
                  _RegionReportView(rows: _regionRows),
                  _ProductReportView(rows: _productRows),
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
  const _RegionReportView({required this.rows});

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
      itemCount: rows!.length,
      itemBuilder: (_, i) {
        final r = rows![i];
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
  const _ProductReportView({required this.rows});

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
      itemCount: rows!.length,
      itemBuilder: (_, i) {
        final p = rows![i];
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
