import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
import 'daily_summary_page.dart';

/// "سجل التسويات" — structured history of completed delegate-shift
/// settlements (DelegateSettlementRecord, written by
/// AdminDelegateController::settleDelegate()). Reachable from the التوزيع
/// sub-menu, alongside طلبات التسليم — same list/filter/pagination
/// structure as admin_sales_collections_page.dart's _SalesTab (date-range
/// picker + load-more pagination, AdminRemoteDataSource called directly
/// rather than through the shared AdminBloc, per that page's established
/// convention), plus a delegate filter dropdown.
class AdminSettlementHistoryPage extends StatefulWidget {
  const AdminSettlementHistoryPage({super.key});

  @override
  State<AdminSettlementHistoryPage> createState() => _AdminSettlementHistoryPageState();
}

class _AdminSettlementHistoryPageState extends State<AdminSettlementHistoryPage> {
  final _remote = sl<AdminRemoteDataSource>();

  List<DelegateModel> _delegates = [];
  int? _delegateId;
  DateTimeRange? _range;

  List<SettlementRecordModel> _rows = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDelegates();
    _load();
  }

  Future<void> _loadDelegates() async {
    try {
      final delegates = await _remote.fetchDelegates();
      if (mounted) setState(() => _delegates = delegates);
    } catch (_) {
      // Non-fatal — the delegate filter just stays empty; the list itself
      // still loads unfiltered.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await _remote.fetchSettlementHistory(
        delegateId: _delegateId,
        dateFrom: _range != null ? fmt.format(_range!.start) : null,
        dateTo: _range != null ? fmt.format(_range!.end) : null,
        page: 1,
      );
      setState(() {
        _rows = page.data;
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'فشل تحميل سجل التسويات.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await _remote.fetchSettlementHistory(
        delegateId: _delegateId,
        dateFrom: _range != null ? fmt.format(_range!.start) : null,
        dateTo: _range != null ? fmt.format(_range!.end) : null,
        page: _currentPage + 1,
      );
      setState(() {
        _rows = [..._rows, ...page.data];
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange:
          _range ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (range != null) {
      setState(() => _range = range);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سجل التسويات')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _delegateId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المندوب', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('كل المناديب')),
                      ..._delegates.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
                    ],
                    onChanged: (v) {
                      setState(() => _delegateId = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      _range == null
                          ? 'كل الفترات'
                          : '${DateFormat('yyyy-MM-dd').format(_range!.start)} — ${DateFormat('yyyy-MM-dd').format(_range!.end)}',
                    ),
                  ),
                ),
                if (_range != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _range = null);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return const Center(
          child: Text('لا توجد تسويات في هذه الفترة.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length + 1,
        itemBuilder: (_, i) {
          if (i == _rows.length) {
            if (!_hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: const Text('تحميل المزيد')),
              ),
            );
          }
          return _SettlementCard(record: _rows[i]);
        },
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  final SettlementRecordModel record;
  const _SettlementCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final varianceColor = record.cashVariance == 0
        ? AppTheme.textMuted
        : record.cashVariance > 0
            ? AppTheme.secondary
            : AppTheme.danger;

    return Card(
      color: AppTheme.cardBg,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.delegateName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('تحميلة #${record.loadingId}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd HH:mm').format(record.settledAt),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DailySummaryPage(settlementId: record.id),
                        ),
                      ),
                      icon: const Icon(Icons.summarize_outlined, size: 20, color: AppTheme.primary),
                      tooltip: 'ملخص اليوم',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
            if (record.isBackfilled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 13, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text('بيانات تاريخية غير مكتملة',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade800)),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'المبيعات',
                    value: record.grossSales != null ? record.grossSales!.toStringAsFixed(0) : '—',
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: 'النقد المتوقع',
                    value: record.expectedCash.toStringAsFixed(0),
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: 'النقد الفعلي',
                    value: record.physicalCash.toStringAsFixed(0),
                    color: AppTheme.secondary,
                    subtitle: record.treasuryName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'الفارق',
                    value: record.cashVariance.toStringAsFixed(0),
                    color: varianceColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: 'المحفظة الإلكترونية',
                    value: record.walletAmount.toStringAsFixed(0),
                    color: AppTheme.accent,
                    subtitle: record.walletTreasuryName,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    label: 'الخصومات',
                    value: record.totalDeductions > 0 ? record.totalDeductions.toStringAsFixed(0) : '—',
                    color: record.totalDeductions > 0 ? AppTheme.danger : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            if (record.settledByName != null) ...[
              const SizedBox(height: 8),
              Text('تمت بواسطة: ${record.settledByName}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  const _StatBox({required this.label, required this.value, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
