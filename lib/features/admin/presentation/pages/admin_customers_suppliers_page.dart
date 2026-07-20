import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../delegate/presentation/pages/customer_invoice_history_page.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// بيانات العملاء والموردين — تصفّح للإدارة فقط (بحث + رصيد)، دون المرور
/// عبر AdminBloc المشترك (نفس منطق AdminExpensesPage). عرض سجل فواتير عميل
/// معيّن يعيد استخدام CustomerInvoiceHistoryPage كما هي — نفس الشاشة التي
/// يستخدمها المندوب لعرض سجل أي عميل، فهي غير مرتبطة بمندوب بعينه أصلاً.
class AdminCustomersSuppliersPage extends StatefulWidget {
  const AdminCustomersSuppliersPage({super.key});

  @override
  State<AdminCustomersSuppliersPage> createState() =>
      _AdminCustomersSuppliersPageState();
}

class _AdminCustomersSuppliersPageState
    extends State<AdminCustomersSuppliersPage> with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بيانات العملاء والموردين'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'العملاء'),
            Tab(text: 'الموردون'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CustomersTab(remote: _remote),
          _SuppliersTab(remote: _remote),
        ],
      ),
    );
  }
}

// ─── Customers tab ───────────────────────────────────────────────────────────

class _CustomersTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _CustomersTab({required this.remote});

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<CustomerModel> _customers = [];
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

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.remote.fetchCustomers(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _customers = page.data;
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل قائمة العملاء.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.remote.fetchCustomers(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        page: _currentPage + 1,
      );
      setState(() {
        _customers.addAll(page.data);
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الهاتف...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_customers.isEmpty) {
      return const Center(
          child: Text('لا يوجد عملاء مطابقون.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _customers.length + 1,
        itemBuilder: (_, i) {
          if (i == _customers.length) {
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
          final c = _customers[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: const Icon(Icons.person_outline, color: AppTheme.primary),
              ),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([
                if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
                if (c.regionName != null) c.regionName!,
              ].join(' • '), style: const TextStyle(fontSize: 12)),
              trailing: Text(
                c.balance.toStringAsFixed(0),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: c.balance > 0 ? AppTheme.danger : AppTheme.secondary,
                ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CustomerInvoiceHistoryPage(customerId: c.id, customerName: c.name),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Suppliers tab ───────────────────────────────────────────────────────────

class _SuppliersTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _SuppliersTab({required this.remote});

  @override
  State<_SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<_SuppliersTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<SupplierModel> _suppliers = [];
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

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.remote.fetchSuppliers(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _suppliers = page.data;
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل قائمة الموردين.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.remote.fetchSuppliers(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        page: _currentPage + 1,
      );
      setState(() {
        _suppliers.addAll(page.data);
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الهاتف...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_suppliers.isEmpty) {
      return const Center(
          child: Text('لا يوجد موردون مطابقون.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _suppliers.length + 1,
        itemBuilder: (_, i) {
          if (i == _suppliers.length) {
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
          final s = _suppliers[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                child: const Icon(Icons.local_shipping_outlined, color: AppTheme.secondary),
              ),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: s.phone != null && s.phone!.isNotEmpty
                  ? Text(s.phone!, style: const TextStyle(fontSize: 12))
                  : null,
              trailing: Text(
                s.balance.toStringAsFixed(0),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: s.balance > 0 ? AppTheme.danger : AppTheme.secondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
