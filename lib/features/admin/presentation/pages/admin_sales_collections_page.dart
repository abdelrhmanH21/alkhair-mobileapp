import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';
import '../../../delegate/data/models/client_model.dart';
import '../../../delegate/presentation/widgets/client_search_field.dart';
import '../../../delegate/presentation/pages/invoice_detail_page.dart';

/// المبيعات والتحصيلات — قائمة موحدة لفواتير الويب وتطبيق المندوب (نفس
/// GET /sales/combined التي تستخدمها شاشة الويب "المبيعات")، بالإضافة إلى
/// سجل التحصيلات من العملاء (GET /payment-collections?type=collection).
/// تستدعي AdminRemoteDataSource مباشرة دون المرور عبر AdminBloc المشترك،
/// بنفس أسلوب AdminExpensesPage/AdminCustomersSuppliersPage. معاينة فاتورة
/// مندوب تعيد استخدام InvoiceDetailPage/ReceiptPreviewCard كما هي — نفس
/// الشاشة التي يفتحها المندوب لفواتيره، فهي غير مقيدة بمندوب بعينه للإدارة.
class AdminSalesCollectionsPage extends StatefulWidget {
  const AdminSalesCollectionsPage({super.key});

  @override
  State<AdminSalesCollectionsPage> createState() => _AdminSalesCollectionsPageState();
}

class _AdminSalesCollectionsPageState extends State<AdminSalesCollectionsPage>
    with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final TabController _tabController = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  Future<void> Function()? _reloadCollections;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openCollectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AdminCollectionFormSheet(remote: _remote),
    ).then((saved) {
      if (saved == true) _reloadCollections?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات والتحصيلات'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'المبيعات'),
            Tab(text: 'السداد والتحصيلات'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton.extended(
              onPressed: _openCollectionSheet,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('تحصيل من عميل'),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _SalesTab(remote: _remote),
          _CollectionsTab(
            remote: _remote,
            registerReload: (fn) => _reloadCollections = fn,
          ),
        ],
      ),
    );
  }
}

// ─── Sales tab ───────────────────────────────────────────────────────────────

class _SalesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _SalesTab({required this.remote});

  @override
  State<_SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<_SalesTab> {
  DateTimeRange? _range;
  List<SalesCombinedRowModel> _rows = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
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
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchSalesCombined(
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
        _error = 'فشل تحميل المبيعات.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchSalesCombined(
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

  void _openRow(SalesCombinedRowModel row) {
    if (!row.isDelegateSourced) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceId: row.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return const Center(
          child: Text('لا توجد فواتير في هذه الفترة.', style: TextStyle(color: Colors.grey)));
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
          final row = _rows[i];
          return Card(
            color: AppTheme.cardBg,
            surfaceTintColor: Colors.transparent,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              onTap: row.isDelegateSourced ? () => _openRow(row) : null,
              leading: CircleAvatar(
                backgroundColor:
                    (row.isDelegateSourced ? AppTheme.accent : AppTheme.secondary)
                        .withValues(alpha: 0.12),
                child: Icon(
                  row.isDelegateSourced ? Icons.motorcycle_outlined : Icons.storefront_outlined,
                  color: row.isDelegateSourced ? AppTheme.accent : AppTheme.secondary,
                ),
              ),
              title: Text(row.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${row.customerName}${row.repName != null ? ' • ${row.repName}' : ''}\n'
                '${DateFormat('yyyy-MM-dd').format(row.date)} • ${row.isDelegateSourced ? 'تطبيق المندوب' : 'نظام الويب'}',
                style: const TextStyle(fontSize: 11),
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(row.total.toStringAsFixed(0),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  Text(_statusLabel(row.paymentStatus),
                      style: TextStyle(fontSize: 10, color: _statusColor(row.paymentStatus))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'paid' => 'مدفوع',
        'partial' => 'جزئي',
        _ => 'غير مدفوع',
      };

  Color _statusColor(String status) => switch (status) {
        'paid' => AppTheme.secondary,
        'partial' => AppTheme.accent,
        _ => AppTheme.danger,
      };
}

// ─── Collections tab ─────────────────────────────────────────────────────────

class _CollectionsTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final void Function(Future<void> Function())? registerReload;
  const _CollectionsTab({required this.remote, this.registerReload});

  @override
  State<_CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<_CollectionsTab> {
  DateTimeRange? _range;
  List<CollectionModel> _rows = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.registerReload?.call(_load);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchCollections(
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
        _error = 'فشل تحميل التحصيلات.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final page = await widget.remote.fetchCollections(
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return const Center(
          child: Text('لا توجد تحصيلات في هذه الفترة.', style: TextStyle(color: Colors.grey)));
    }
    final total = _rows.fold<double>(0, (s, c) => s + c.amount);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length + 2,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('إجمالي التحصيلات (هذه الصفحة)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(total.toStringAsFixed(2),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: AppTheme.secondary, fontSize: 15)),
                ],
              ),
            );
          }
          final idx = i - 1;
          if (idx == _rows.length) {
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
          final c = _rows[idx];
          return Card(
            color: AppTheme.cardBg,
            surfaceTintColor: Colors.transparent,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.12),
                child: const Icon(Icons.payments_outlined, color: AppTheme.secondary),
              ),
              title: Text(c.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${DateFormat('yyyy-MM-dd').format(c.date)} • ${c.treasuryName}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(c.amount.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary)),
            ),
          );
        },
      ),
    );
  }
}

// ─── تحصيل من عميل (admin-initiated, not scoped to any delegate shift) ──────

class _AdminCollectionFormSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _AdminCollectionFormSheet({required this.remote});

  @override
  State<_AdminCollectionFormSheet> createState() => _AdminCollectionFormSheetState();
}

class _AdminCollectionFormSheetState extends State<_AdminCollectionFormSheet> {
  ClientModel? _selectedClient;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<ClientModel> _searchResults = [];
  bool _searchLoading = false;

  List<TreasuryModel> _treasuries = [];
  int? _treasuryId;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;
  bool _loadingTreasuries = true;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    _loadTreasuries();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) _search('');
  }

  Future<void> _loadTreasuries() async {
    try {
      final treasuries = await widget.remote.fetchTreasuries();
      setState(() {
        _treasuries = treasuries;
        _treasuryId = treasuries.where((t) => t.isDefault).map((t) => t.id).firstOrNull ??
            (treasuries.isNotEmpty ? treasuries.first.id : null);
        _loadingTreasuries = false;
      });
    } catch (_) {
      setState(() => _loadingTreasuries = false);
    }
  }

  Future<void> _search(String q) async {
    setState(() => _searchLoading = true);
    try {
      final results = await widget.remote.searchCustomers(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedClient == null) {
      AppSnackbar.showError(context, 'يرجى اختيار عميل أولاً.');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    if (_treasuryId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.remote.submitCustomerCollection(
        customerId: _selectedClient!.id,
        treasuryId: _treasuryId!,
        amount: amount,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      AppSnackbar.showSuccess(context, 'تم تسجيل التحصيل بنجاح.');
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل تسجيل التحصيل.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تحصيل من عميل', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ClientSearchField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            results: _searchResults,
            isLoading: _searchLoading,
            selectedClient: _selectedClient,
            onSearch: _search,
            onSelect: (c) => setState(() {
              _selectedClient = c;
              _searchCtrl.text = c.name;
              _searchResults.clear();
            }),
            onAddNew: () =>
                AppSnackbar.showInfo(context, 'إضافة عميل جديد متاحة من شاشة بيانات العملاء.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ المحصّل', hintText: '0'),
          ),
          const SizedBox(height: 12),
          if (!_loadingTreasuries)
            DropdownButtonFormField<int>(
              initialValue: _treasuryId,
              decoration: const InputDecoration(labelText: 'الخزينة'),
              items: _treasuries.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
              onChanged: (v) => setState(() => _treasuryId = v),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline),
            label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ التحصيل'),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
