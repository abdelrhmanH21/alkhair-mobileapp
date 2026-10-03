import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/report_export.dart';
import '../../../admin/data/datasources/admin_remote_datasource.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/client_model.dart';
import '../../data/models/report_models.dart';
import '../widgets/client_search_field.dart';

enum _ReportPeriod { month, week, custom }
enum _ReportKind { region, product }

/// تقارير المندوب — بيانات مبيعاته (المناطق/الأصناف) لفترة قابلة للاختيار.
/// مصدر مصدرها الوحيد: DelegateReportController::byRegion()/byProduct()، نفس
/// أسلوب جلب البيانات المستخدم في CommissionBreakdownPage.
/// Every delegate — "مندوب حر السعر" included — gets exactly these two tabs.
///
/// Admin/manager (who reach this same page from the admin drawer, with the
/// region/product reports aggregated company-wide) additionally get
/// "تقرير الخزائن" and "تقرير الموردين" — company-wide only, never shown to
/// a delegate — with the same period chips and PDF/Excel export — plus
/// "كشف حساب عميل": pick one customer, see their full chronological debt
/// ledger (running balance after every row). That tab carries its own
/// OPTIONAL date range (default: full history) instead of the shared chips.
class DelegateReportsPage extends StatefulWidget {
  /// Overridable for tests; defaults to the service-locator instance.
  final AdminRemoteDataSource? adminRemote;
  const DelegateReportsPage({super.key, this.adminRemote});

  @override
  State<DelegateReportsPage> createState() => _DelegateReportsPageState();
}

class _DelegateReportsPageState extends State<DelegateReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final bool _isAdmin;
  static const int _customerLedgerTabIndex = 4; // admin only
  bool get _showPeriodChips => !(_isAdmin && _tabController.index == _customerLedgerTabIndex);
  int _lastTabIndex = 0;
  _ReportPeriod _period = _ReportPeriod.month;
  DateTimeRange? _customRange;

  List<RegionReportRowModel>? _regionRows;
  List<ProductReportRowModel>? _productRows;
  List<TreasuryReportRowModel>? _treasuryRows;
  List<SupplierReportRowModel>? _supplierRows;
  // Bumped on every period change so a slower response for an older period
  // can never overwrite the rows of the one now selected.
  int _adminFetchGeneration = 0;

  // This page lives forever behind DashboardSection's card (and every other
  // tab in DelegateHomePage's IndexedStack), all sharing one DelegateBloc.
  // Tracks this page's own two outstanding fetches by requestId so an
  // unrelated DelegateFailure elsewhere can never surface here.
  final _tracker = RequestTracker<_ReportKind>();

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _isAdmin = authState is AuthAuthenticated && authState.user.isAdmin;
    _tabController = TabController(length: 2 + (_isAdmin ? 3 : 0), vsync: this);
    if (_isAdmin) _tabController.addListener(_onTabChanged);
    _fetchReports();
  }

  @override
  void dispose() {
    if (_isAdmin) _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final index = _tabController.index;
    if (index == _lastTabIndex) return;
    _lastTabIndex = index;
    setState(() {}); // the period chips are hidden on the ledger tab
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
    if (_isAdmin) _fetchAdminReports(params);
  }

  /// تقرير الخزائن / تقرير الموردين — plain datasource calls (admin-only
  /// data, nothing to share through the delegate bloc).
  Future<void> _fetchAdminReports(({String? period, String? dateFrom, String? dateTo}) params) async {
    final generation = ++_adminFetchGeneration;
    final remote = widget.adminRemote ?? sl<AdminRemoteDataSource>();
    Future<void> load<T>(Future<List<T>> Function() fetch, void Function(List<T>) apply) async {
      try {
        final rows = await fetch();
        if (mounted && generation == _adminFetchGeneration) setState(() => apply(rows));
      } on DioException catch (e) {
        if (!mounted || generation != _adminFetchGeneration) return;
        setState(() => apply(<T>[]));
        AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'تعذر تحميل التقرير.');
      } catch (_) {
        if (!mounted || generation != _adminFetchGeneration) return;
        setState(() => apply(<T>[]));
        AppSnackbar.showError(context, 'تعذر تحميل التقرير.');
      }
    }

    await Future.wait([
      load<TreasuryReportRowModel>(
        () => remote.fetchTreasuryReport(period: params.period, dateFrom: params.dateFrom, dateTo: params.dateTo),
        (rows) => _treasuryRows = rows,
      ),
      load<SupplierReportRowModel>(
        () => remote.fetchSupplierReport(period: params.period, dateFrom: params.dateFrom, dateTo: params.dateTo),
        (rows) => _supplierRows = rows,
      ),
    ]);
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
        _treasuryRows = null;
        _supplierRows = null;
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
      _treasuryRows = null;
      _supplierRows = null;
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
          isScrollable: _isAdmin,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'تقرير المناطق'),
            const Tab(text: 'تقرير الأصناف'),
            if (_isAdmin) const Tab(text: 'تقرير الخزائن'),
            if (_isAdmin) const Tab(text: 'تقرير الموردين'),
            if (_isAdmin) const Tab(text: 'كشف حساب عميل'),
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
            if (_showPeriodChips)
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
                  if (_isAdmin) _TreasuryReportView(rows: _treasuryRows, periodLabel: _periodLabel),
                  if (_isAdmin) _SupplierReportView(rows: _supplierRows, periodLabel: _periodLabel),
                  if (_isAdmin)
                    CustomerLedgerReportView(remote: widget.adminRemote ?? sl<AdminRemoteDataSource>()),
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
          child: Text('لا توجد مبيعات في هذه الفترة.', style: TextStyle(color: AppTheme.textMuted)));
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
          child: Text('لا توجد مبيعات في هذه الفترة.', style: TextStyle(color: AppTheme.textMuted)));
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

class _TreasuryReportView extends StatelessWidget {
  final List<TreasuryReportRowModel>? rows;
  final String periodLabel;
  const _TreasuryReportView({required this.rows, required this.periodLabel});

  ReportExportData _exportData() {
    final r = rows ?? [];
    final totalBalance = r.fold(0.0, (s, row) => s + row.balance);
    final totalCredit = r.fold(0.0, (s, row) => s + row.totalCredit);
    final totalDebit = r.fold(0.0, (s, row) => s + row.totalDebit);
    return ReportExportData(
      title: 'تقرير الخزائن',
      period: periodLabel,
      headers: const ['الخزينة', 'الرصيد الحالي', 'إجمالي الوارد', 'إجمالي المنصرف', 'صافي الحركة'],
      rows: r
          .map((row) => [
                row.treasuryName,
                row.balance.toStringAsFixed(2),
                row.totalCredit.toStringAsFixed(2),
                row.totalDebit.toStringAsFixed(2),
                row.netMovement.toStringAsFixed(2),
              ])
          .toList(),
      totals: [
        'الإجمالي',
        totalBalance.toStringAsFixed(2),
        totalCredit.toStringAsFixed(2),
        totalDebit.toStringAsFixed(2),
        (totalCredit - totalDebit).toStringAsFixed(2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows!.isEmpty) {
      return const Center(child: Text('لا توجد خزائن.', style: TextStyle(color: AppTheme.textMuted)));
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
                      child: Text(r.treasuryName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Text(r.balance.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ReportMiniStat(label: 'الوارد', value: r.totalCredit.toStringAsFixed(2)),
                    _ReportMiniStat(label: 'المنصرف', value: r.totalDebit.toStringAsFixed(2)),
                    _ReportMiniStat(label: 'صافي الحركة', value: r.netMovement.toStringAsFixed(2)),
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

class _SupplierReportView extends StatelessWidget {
  final List<SupplierReportRowModel>? rows;
  final String periodLabel;
  const _SupplierReportView({required this.rows, required this.periodLabel});

  ReportExportData _exportData() {
    final r = rows ?? [];
    final totalBalance = r.fold(0.0, (s, row) => s + row.balance);
    final totalPurchases = r.fold(0.0, (s, row) => s + row.totalPurchases);
    final totalPaid = r.fold(0.0, (s, row) => s + row.totalPaid);
    return ReportExportData(
      title: 'تقرير الموردين',
      period: periodLabel,
      headers: const ['المورد', 'الرصيد الحالي', 'عدد الفواتير', 'إجمالي المشتريات', 'المدفوع'],
      rows: r
          .map((row) => [
                row.supplierName,
                row.balance.toStringAsFixed(2),
                '${row.purchaseCount}',
                row.totalPurchases.toStringAsFixed(2),
                row.totalPaid.toStringAsFixed(2),
              ])
          .toList(),
      totals: [
        'الإجمالي',
        totalBalance.toStringAsFixed(2),
        '-',
        totalPurchases.toStringAsFixed(2),
        totalPaid.toStringAsFixed(2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows!.isEmpty) {
      return const Center(child: Text('لا يوجد موردون.', style: TextStyle(color: AppTheme.textMuted)));
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
                      child: Text(r.supplierName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Text(r.balance.toStringAsFixed(2),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: r.balance > 0 ? AppTheme.danger : AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ReportMiniStat(label: 'عدد الفواتير', value: '${r.purchaseCount}'),
                    _ReportMiniStat(label: 'المشتريات', value: r.totalPurchases.toStringAsFixed(2)),
                    _ReportMiniStat(label: 'المدفوع', value: r.totalPaid.toStringAsFixed(2)),
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

// ─── كشف حساب عميل ─────────────────────────────────────────────────────────────

/// Builds the PDF/Excel payload for a customer ledger — top-level so the
/// export columns are unit-testable without pumping the page.
ReportExportData customerLedgerExportData(CustomerLedgerModel l) {
  final fmt = NumberFormat('#,##0.00');
  return ReportExportData(
    title: 'كشف حساب عميل — ${l.customerName}',
    period: customerLedgerPeriodLabel(l),
    headers: const ['التاريخ', 'النوع', 'البيان', 'المبلغ', 'رصيد بعدها'],
    rows: l.rows
        .map((r) => [
              r.date,
              r.typeLabel,
              r.actor == null ? r.description : '${r.description} — ${r.actor}',
              r.isBalanceMarker ? '-' : fmt.format(r.amount),
              fmt.format(r.balanceAfter),
            ])
        .toList(),
    totals: [
      l.periodTo == null ? 'إجمالي المديونية' : 'الرصيد في نهاية الفترة',
      '-',
      'مدين ${fmt.format(l.totalDebit)} / دائن ${fmt.format(l.totalCredit)}',
      '-',
      fmt.format(l.closingBalance),
    ],
  );
}

String customerLedgerPeriodLabel(CustomerLedgerModel l) => l.isFullHistory
    ? 'كامل السجل'
    : '${l.periodFrom ?? 'البداية'} — ${l.periodTo ?? 'اليوم'}';

class CustomerLedgerReportView extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const CustomerLedgerReportView({super.key, required this.remote});

  @override
  State<CustomerLedgerReportView> createState() => _CustomerLedgerReportViewState();
}

class _CustomerLedgerReportViewState extends State<CustomerLedgerReportView>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<ClientModel> _results = [];
  bool _searchLoading = false;
  ClientModel? _client;
  DateTimeRange? _range; // null = full history
  CustomerLedgerModel? _ledger;
  bool _loading = false;
  // Bumped per request so a slower response for a previously selected
  // customer/range can never overwrite the one now shown.
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) _search('');
  }

  Future<void> _search(String q) async {
    setState(() => _searchLoading = true);
    try {
      final results = await widget.remote.searchCustomers(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final generation = ++_generation;
    final fmt = DateFormat('yyyy-MM-dd');
    setState(() => _loading = true);
    try {
      final ledger = await widget.remote.fetchCustomerLedger(
        client.id,
        dateFrom: _range == null ? null : fmt.format(_range!.start),
        dateTo: _range == null ? null : fmt.format(_range!.end),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _ledger = ledger;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _loading = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'تعذر تحميل كشف الحساب.');
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _loading = false);
      AppSnackbar.showError(context, 'تعذر تحميل كشف الحساب.');
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
    );
    if (range == null) return;
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ledger = _ledger;
    final amountFmt = NumberFormat('#,##0.00');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ClientSearchField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          results: _results,
          isLoading: _searchLoading,
          selectedClient: _client,
          onSearch: _search,
          onSelect: (c) {
            setState(() {
              _client = c;
              _searchCtrl.text = c.name;
              _results = [];
              _ledger = null;
            });
            FocusScope.of(context).unfocus();
            _load();
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('كامل السجل'),
                selected: _range == null,
                onSelected: (_) {
                  if (_range == null) return;
                  setState(() => _range = null);
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: Text(_range == null
                    ? 'نطاق مخصص'
                    : '${DateFormat('yy-MM-dd').format(_range!.start)}..${DateFormat('yy-MM-dd').format(_range!.end)}'),
                selected: _range != null,
                onSelected: (_) => _pickRange(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_client == null)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text('ابحث عن العميل لعرض كشف حسابه الكامل.',
                textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
          )
        else if (_loading && ledger == null)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (ledger != null) ...[
          _ExportButtonsRow(buildData: () => customerLedgerExportData(ledger)),
          Card(
            color: AppTheme.primary.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ReportMiniStat(label: 'مدين', value: amountFmt.format(ledger.totalDebit)),
                  _ReportMiniStat(label: 'دائن', value: amountFmt.format(ledger.totalCredit)),
                  _ReportMiniStat(label: 'المديونية الحالية', value: amountFmt.format(ledger.currentBalance)),
                ],
              ),
            ),
          ),
          if (ledger.unexplainedTotal != 0)
            Card(
              color: AppTheme.accent.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'يوجد فرق غير مفسَّر بقيمة ${amountFmt.format(ledger.unexplainedTotal)} — تغيير في الرصيد لا يقابله سجل.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ...ledger.rows.map((r) => _CustomerLedgerRowCard(row: r, fmt: amountFmt)),
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              title: Text(ledger.periodTo == null ? 'إجمالي المديونية الحالية' : 'الرصيد في نهاية الفترة',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(amountFmt.format(ledger.closingBalance),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomerLedgerRowCard extends StatelessWidget {
  final CustomerLedgerRowModel row;
  final NumberFormat fmt;
  const _CustomerLedgerRowCard({required this.row, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final Color amountColor = row.isBalanceMarker || row.amount == 0
        ? AppTheme.textMuted
        : (row.amount > 0 ? AppTheme.danger : Colors.green.shade700);
    final Color? bg = switch (row.type) {
      'unexplained' => AppTheme.accent.withValues(alpha: 0.12),
      'debt_audit' => AppTheme.primary.withValues(alpha: 0.05),
      _ => null,
    };
    return Card(
      color: bg,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(row.typeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(row.date, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 4),
            Text(row.actor == null ? row.description : '${row.description} — ${row.actor}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.isBalanceMarker ? '' : '${row.amount > 0 ? '+' : ''}${fmt.format(row.amount)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: amountColor),
                  ),
                ),
                Text('رصيد بعدها: ${fmt.format(row.balanceAfter)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Export buttons row (shared by every report tab) ──────────────────────────

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
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      );
}
