import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../delegate/data/models/customer_region_model.dart';
import '../../../delegate/presentation/pages/customer_invoice_history_page.dart';
import '../../../delegate/presentation/widgets/add_client_sheet.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// العملاء / الموردون / مناطق التوزيع — three standalone list+detail
/// sections with full CRUD, each reusing the exact same backend
/// endpoints/validation the web already uses (CustomerController,
/// SupplierController, CustomerRegionController — all already reachable
/// with the mobile admin/manager bearer token, no backend changes needed).
/// Direct AdminRemoteDataSource calls, not AdminBloc (same convention as
/// the rest of this page's siblings — see AdminExpensesPage).
class AdminCustomersSuppliersPage extends StatefulWidget {
  const AdminCustomersSuppliersPage({super.key});

  @override
  State<AdminCustomersSuppliersPage> createState() =>
      _AdminCustomersSuppliersPageState();
}

class _AdminCustomersSuppliersPageState
    extends State<AdminCustomersSuppliersPage> with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final TabController _tabController = TabController(length: 3, vsync: this);

  final _customersKey = GlobalKey<_CustomersTabState>();
  final _suppliersKey = GlobalKey<_SuppliersTabState>();
  final _regionsKey = GlobalKey<_RegionsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onAddPressed() {
    switch (_tabController.index) {
      case 0:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddClientSheet(
            onClientAdded: (_) => _customersKey.currentState?.reload(),
          ),
        );
        break;
      case 1:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _SupplierFormSheet(
            remote: _remote,
            onSaved: () => _suppliersKey.currentState?.reload(),
          ),
        );
        break;
      case 2:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _RegionFormSheet(
            remote: _remote,
            onSaved: () => _regionsKey.currentState?.reload(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('العملاء والموردون'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'العملاء'),
            Tab(text: 'الموردون'),
            Tab(text: 'مناطق التوزيع'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _CustomersTab(key: _customersKey, remote: _remote),
          _SuppliersTab(key: _suppliersKey, remote: _remote),
          _RegionsTab(key: _regionsKey, remote: _remote),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onAddPressed,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Customers tab ───────────────────────────────────────────────────────────

class _CustomersTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _CustomersTab({super.key, required this.remote});

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

  void reload() => _load();

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

  Future<void> _openEdit(CustomerModel c) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerEditSheet(remote: widget.remote, customer: c),
    );
    _load();
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
        if (!_loading && _error == null && _customers.isNotEmpty)
          const _ColumnHeadersRow(leadingLabel: 'العميل', trailingLabel: 'الرصيد'),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_customers.isEmpty) {
      return const Center(
          child: Text('لا يوجد عملاء مطابقون.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0).copyWith(bottom: 80),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.balance.toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: c.balance > 0 ? AppTheme.danger : AppTheme.secondary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted),
                    onPressed: () => _openEdit(c),
                  ),
                ],
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

class _CustomerEditSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final CustomerModel customer;
  const _CustomerEditSheet({required this.remote, required this.customer});

  @override
  State<_CustomerEditSheet> createState() => _CustomerEditSheetState();
}

class _CustomerEditSheetState extends State<_CustomerEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.customer.name);
  late final _phoneCtrl = TextEditingController(text: widget.customer.phone ?? '');

  List<CustomerRegionModel> _regions = [];
  CustomerRegionModel? _selectedRegion;
  bool _loadingRegions = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await widget.remote.fetchAllCustomerRegions();
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _selectedRegion = widget.customer.regionName == null
            ? null
            : regions
                .cast<CustomerRegionModel?>()
                .firstWhere((r) => r!.name == widget.customer.regionName, orElse: () => null);
        _loadingRegions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRegions = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.remote.updateCustomer(
        id: widget.customer.id,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        customerRegionId: _selectedRegion?.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.showSuccess(context, 'تم تحديث بيانات العميل بنجاح.');
    } on DioException catch (e) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل تحديث العميل.');
    } catch (_) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('تعديل بيانات العميل',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم العميل *', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 10),
            if (_loadingRegions)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              DropdownButtonFormField<CustomerRegionModel>(
                initialValue: _selectedRegion,
                hint: const Text('اختر منطقة'),
                decoration: const InputDecoration(labelText: 'المنطقة', prefixIcon: Icon(Icons.location_on_outlined)),
                items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
                onChanged: (v) => setState(() => _selectedRegion = v),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ التعديلات'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Suppliers tab ───────────────────────────────────────────────────────────

class _SuppliersTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _SuppliersTab({super.key, required this.remote});

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

  void reload() => _load();

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

  Future<void> _openEdit(SupplierModel s) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SupplierFormSheet(remote: widget.remote, supplier: s, onSaved: _load),
    );
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
        if (!_loading && _error == null && _suppliers.isNotEmpty)
          const _ColumnHeadersRow(leadingLabel: 'المورد', trailingLabel: 'الرصيد'),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_suppliers.isEmpty) {
      return const Center(
          child: Text('لا يوجد موردون مطابقون.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0).copyWith(bottom: 80),
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.balance.toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: s.balance > 0 ? AppTheme.danger : AppTheme.secondary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted),
                    onPressed: () => _openEdit(s),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SupplierFormSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final SupplierModel? supplier; // null = create
  final VoidCallback onSaved;
  const _SupplierFormSheet({required this.remote, this.supplier, required this.onSaved});

  @override
  State<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<_SupplierFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _balanceCtrl =
      TextEditingController(text: widget.supplier == null ? '' : widget.supplier!.balance.toStringAsFixed(2));
  bool _saving = false;

  bool get _isEdit => widget.supplier != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.remote.updateSupplier(
          id: widget.supplier!.id,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
      } else {
        await widget.remote.createSupplier(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          balance: double.tryParse(_balanceCtrl.text),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      AppSnackbar.showSuccess(context, _isEdit ? 'تم تحديث بيانات المورد بنجاح.' : 'تمت إضافة المورد بنجاح.');
    } on DioException catch (e) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل حفظ المورد.');
    } catch (_) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_isEdit ? 'تعديل بيانات المورد' : 'إضافة مورد جديد',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'اسم المورد *', prefixIcon: Icon(Icons.local_shipping_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'رصيد افتتاحي مستحق', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── مناطق التوزيع tab ───────────────────────────────────────────────────────

class _RegionsTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _RegionsTab({super.key, required this.remote});

  @override
  State<_RegionsTab> createState() => _RegionsTabState();
}

class _RegionsTabState extends State<_RegionsTab> {
  bool _loading = true;
  String? _error;
  List<CustomerRegionModel> _regions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final regions = await widget.remote.fetchAllCustomerRegions();
      if (!mounted) return;
      setState(() {
        _regions = regions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل مناطق التوزيع.';
      });
    }
  }

  Future<void> _toggleActive(CustomerRegionModel r) async {
    try {
      await widget.remote.updateCustomerRegion(id: r.id, isActive: !r.isActive);
      _load();
    } on DioException catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل تحديث المنطقة.');
    }
  }

  Future<void> _openEdit(CustomerRegionModel r) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RegionFormSheet(remote: widget.remote, region: r, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    if (_regions.isEmpty) {
      return const Center(
          child: Text('لا توجد مناطق توزيع مسجلة.', style: TextStyle(color: AppTheme.textMuted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8).copyWith(bottom: 80),
        itemCount: _regions.length,
        itemBuilder: (_, i) {
          final r = _regions[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                child: const Icon(Icons.location_on_outlined, color: AppTheme.accent),
              ),
              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(r.isActive ? 'مفعّلة' : 'غير مفعّلة',
                  style: TextStyle(fontSize: 12, color: r.isActive ? Colors.green.shade700 : AppTheme.danger)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(value: r.isActive, onChanged: (_) => _toggleActive(r)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textMuted),
                    onPressed: () => _openEdit(r),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RegionFormSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final CustomerRegionModel? region; // null = create
  final VoidCallback onSaved;
  const _RegionFormSheet({required this.remote, this.region, required this.onSaved});

  @override
  State<_RegionFormSheet> createState() => _RegionFormSheetState();
}

class _RegionFormSheetState extends State<_RegionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.region?.name ?? '');
  bool _saving = false;

  bool get _isEdit => widget.region != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await widget.remote.updateCustomerRegion(id: widget.region!.id, name: _nameCtrl.text.trim());
      } else {
        await widget.remote.createCustomerRegion(_nameCtrl.text.trim());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      AppSnackbar.showSuccess(context, _isEdit ? 'تم تحديث المنطقة بنجاح.' : 'تمت إضافة المنطقة بنجاح.');
    } on DioException catch (e) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل حفظ المنطقة.');
    } catch (_) {
      setState(() => _saving = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_isEdit ? 'تعديل منطقة توزيع' : 'إضافة منطقة توزيع',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم المنطقة *', prefixIcon: Icon(Icons.location_on_outlined)),
              validator: (v) => v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: const Text('حفظ'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Column headers (shared by customers/suppliers tabs) ──────────────────
// Each row below is leading-name + trailing-balance with no inline label on
// the number — a bare header makes it clear what the two columns mean
// without relying on color alone (red/green) to convey debt vs. credit.

class _ColumnHeadersRow extends StatelessWidget {
  final String leadingLabel;
  final String trailingLabel;
  const _ColumnHeadersRow({required this.leadingLabel, required this.trailingLabel});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leadingLabel,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
            Text(trailingLabel,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
          ],
        ),
      );
}
