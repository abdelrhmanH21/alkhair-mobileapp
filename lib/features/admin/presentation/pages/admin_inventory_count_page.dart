import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "عملية جرد" — mirrors the web "جرد التصنيع"/"جرد اللبن" page's 4 tabs
/// (JardPage.tsx) exactly: جرد المخازن / جرد الخزائن / جرد المديونيات /
/// جرد ديون الموردين. Every tab hits the same backend logic/endpoints the
/// web page already calls (StocktakingController via the mobile-only
/// collapsed AdminInventoryController, VaultAuditController, DebtAuditController
/// scoped to client_type customer/supplier) — no new backend routes needed,
/// role:admin,manager,accountant / role:admin,manager,warehouse already
/// cover the mobile admin/manager bearer token.
class AdminInventoryCountPage extends StatefulWidget {
  const AdminInventoryCountPage({super.key});

  @override
  State<AdminInventoryCountPage> createState() =>
      _AdminInventoryCountPageState();
}

class _AdminInventoryCountPageState extends State<AdminInventoryCountPage>
    with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عملية جرد'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'جرد المخازن'),
            Tab(text: 'جرد الخزائن'),
            Tab(text: 'جرد المديونيات'),
            Tab(text: 'جرد ديون الموردين'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _WarehouseCountTab(remote: _remote),
          _VaultAuditTab(remote: _remote),
          _DebtAuditTab(remote: _remote, clientType: 'customer', entityLabel: 'العميل'),
          _DebtAuditTab(remote: _remote, clientType: 'supplier', entityLabel: 'المورد'),
        ],
      ),
    );
  }
}

// ─── جرد المخازن ─────────────────────────────────────────────────────────
// Unchanged logic from the original single-tab page — snapshots a
// warehouse's current stock, collects a physical count per item, and
// creates+finalizes a Stocktaking session in one call via
// AdminInventoryController (POST /v1/mobile/admin/inventory-count).

class _WarehouseCountTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _WarehouseCountTab({required this.remote});

  @override
  State<_WarehouseCountTab> createState() => _WarehouseCountTabState();
}

class _WarehouseCountTabState extends State<_WarehouseCountTab> {
  bool _loadingWarehouses = true;
  String? _warehousesError;
  List<SimpleWarehouseModel> _warehouses = [];
  List<TreasuryModel> _treasuries = [];
  List<CustomerModel> _customers = [];

  int? _warehouseId;
  bool _loadingItems = false;
  String? _itemsError;
  List<InventoryCountItemModel> _items = [];
  final Map<String, TextEditingController> _counts = {};

  String _settlementType = 'none';
  int? _treasuryId;
  int? _customerId;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  String _keyFor(InventoryCountItemModel item) => item.itemType == 'product'
      ? 'p${item.productId}'
      : 'r${item.rawMaterialId}';

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _loadingWarehouses = true;
      _warehousesError = null;
    });
    try {
      final warehouses = await widget.remote.fetchWarehouses();
      setState(() {
        _warehouses = warehouses;
        _loadingWarehouses = false;
      });
    } catch (_) {
      setState(() {
        _loadingWarehouses = false;
        _warehousesError = 'فشل تحميل المخازن.';
      });
    }
  }

  Future<void> _onWarehouseChanged(int? warehouseId) async {
    setState(() {
      _warehouseId = warehouseId;
      _items = [];
      for (final c in _counts.values) {
        c.dispose();
      }
      _counts.clear();
    });
    if (warehouseId == null) return;
    setState(() {
      _loadingItems = true;
      _itemsError = null;
    });
    try {
      final items = await widget.remote.fetchInventoryCountItems(warehouseId);
      setState(() {
        _items = items;
        for (final item in items) {
          _counts[_keyFor(item)] = TextEditingController();
        }
        _loadingItems = false;
      });
    } catch (_) {
      setState(() {
        _loadingItems = false;
        _itemsError = 'فشل تحميل أصناف المخزن.';
      });
    }
  }

  Future<void> _loadSettlementRefData() async {
    if (_treasuries.isNotEmpty || _customers.isNotEmpty) return;
    try {
      final results = await Future.wait([
        widget.remote.fetchTreasuries(),
        widget.remote.fetchCustomers(),
      ]);
      setState(() {
        _treasuries = results[0] as List<TreasuryModel>;
        _customers = (results[1] as CustomerPageModel).data;
      });
    } catch (_) {
      // Non-fatal — dropdowns just stay empty until retried.
    }
  }

  Future<void> _submit() async {
    if (_warehouseId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المخزن.');
      return;
    }
    final counts = <Map<String, dynamic>>[];
    for (final item in _items) {
      final text = _counts[_keyFor(item)]?.text ?? '';
      if (text.isEmpty) continue;
      final qty = double.tryParse(text);
      if (qty == null) continue;
      counts.add({
        'item_type': item.itemType,
        if (item.itemType == 'product')
          'product_id': item.productId
        else
          'raw_material_id': item.rawMaterialId,
        'physical_quantity': qty,
      });
    }
    if (counts.isEmpty) {
      AppSnackbar.showError(context, 'أدخل كمية فعلية لصنف واحد على الأقل.');
      return;
    }
    if (_settlementType == 'treasury' && _treasuryId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة للتسوية.');
      return;
    }
    if (_settlementType == 'customer' && _customerId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار العميل للتسوية.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final variance = await widget.remote.submitInventoryCount(
        warehouseId: _warehouseId!,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        settlementType: _settlementType,
        treasuryId: _settlementType == 'treasury' ? _treasuryId : null,
        customerId: _settlementType == 'customer' ? _customerId : null,
        counts: counts,
      );
      if (!mounted) return;
      final msg = variance == 0
          ? 'تم إنهاء الجرد — لا يوجد فرق'
          : variance > 0
              ? 'تم إنهاء الجرد — فائض بقيمة ${variance.toStringAsFixed(2)}'
              : 'تم إنهاء الجرد — عجز بقيمة ${variance.abs().toStringAsFixed(2)}';
      setState(() {
        _submitting = false;
        _warehouseId = null;
        _items = [];
        _counts.clear();
        _settlementType = 'none';
        _treasuryId = null;
        _customerId = null;
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(context, msg);
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context,
          e.response?.data?['message'] as String? ?? 'فشل إنهاء الجرد.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingWarehouses) return const Center(child: CircularProgressIndicator());
    if (_warehousesError != null) {
      return AppErrorView(message: _warehousesError!, onRetry: _loadWarehouses);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<int>(
          initialValue: _warehouseId,
          decoration: const InputDecoration(labelText: 'المخزن'),
          items: _warehouses
              .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
              .toList(),
          onChanged: _onWarehouseChanged,
        ),
        const SizedBox(height: 16),
        if (_loadingItems) const Center(child: CircularProgressIndicator()),
        if (!_loadingItems && _itemsError != null)
          AppErrorView(
            message: _itemsError!,
            onRetry: () => _onWarehouseChanged(_warehouseId),
          ),
        if (!_loadingItems &&
            _itemsError == null &&
            _warehouseId != null &&
            _items.isEmpty)
          const Text('لا توجد أصناف في هذا المخزن.',
              style: TextStyle(color: AppTheme.textMuted)),
        ..._items.map((item) => Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                              'النظام: ${item.systemQuantity.toStringAsFixed(2)} ${item.unit}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _counts[_keyFor(item)],
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                            labelText: 'الفعلي', isDense: true),
                      ),
                    ),
                  ],
                ),
              ),
            )),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('نوع التسوية المالية', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<String>(
            value: 'none',
            groupValue: _settlementType,
            title: const Text('بدون تسوية — تحديث المخزون فقط', style: TextStyle(fontSize: 13)),
            onChanged: (v) => setState(() => _settlementType = v!),
            dense: true,
          ),
          RadioListTile<String>(
            value: 'treasury',
            groupValue: _settlementType,
            title: const Text('تسوية على الخزينة', style: TextStyle(fontSize: 13)),
            onChanged: (v) {
              setState(() => _settlementType = v!);
              _loadSettlementRefData();
            },
            dense: true,
          ),
          RadioListTile<String>(
            value: 'customer',
            groupValue: _settlementType,
            title: const Text('تسوية على مديونية عميل', style: TextStyle(fontSize: 13)),
            onChanged: (v) {
              setState(() => _settlementType = v!);
              _loadSettlementRefData();
            },
            dense: true,
          ),
          if (_settlementType == 'treasury')
            DropdownButtonFormField<int>(
              initialValue: _treasuryId,
              decoration: const InputDecoration(labelText: 'الخزينة'),
              items: _treasuries
                  .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _treasuryId = v),
            ),
          if (_settlementType == 'customer')
            DropdownButtonFormField<int>(
              initialValue: _customerId,
              decoration: const InputDecoration(labelText: 'العميل'),
              items: _customers
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _customerId = v),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? 'جارٍ الحفظ...' : 'تأكيد الجرد وتطبيق التسويات'),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── جرد الخزائن ─────────────────────────────────────────────────────────
// Mirrors VaultAuditTab in JardPage.tsx — pick a treasury, compare its
// system balance to a physical cash count, submit via VaultAuditController
// (POST /vault-audits), which applies the variance to the treasury itself.

class _VaultAuditTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  const _VaultAuditTab({required this.remote});

  @override
  State<_VaultAuditTab> createState() => _VaultAuditTabState();
}

class _VaultAuditTabState extends State<_VaultAuditTab> {
  bool _loading = true;
  String? _error;
  List<TreasuryModel> _treasuries = [];
  List<VaultAuditModel> _history = [];

  TreasuryModel? _selectedTreasury;
  final _balanceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _balanceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.remote.fetchTreasuries(),
        widget.remote.fetchVaultAudits(),
      ]);
      if (!mounted) return;
      setState(() {
        _treasuries = results[0] as List<TreasuryModel>;
        _history = results[1] as List<VaultAuditModel>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل بيانات الخزائن.';
      });
    }
  }

  double? get _variance {
    if (_selectedTreasury == null) return null;
    final phys = double.tryParse(_balanceCtrl.text);
    if (phys == null) return null;
    return phys - _selectedTreasury!.balance;
  }

  Future<void> _submit() async {
    final treasury = _selectedTreasury;
    if (treasury == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة.');
      return;
    }
    final phys = double.tryParse(_balanceCtrl.text);
    if (phys == null) {
      AppSnackbar.showError(context, 'أدخل الرصيد الفعلي.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final variance = await widget.remote.submitVaultAudit(
        treasuryId: treasury.id,
        physicalBalance: phys,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      final msg = variance.abs() < 0.01
          ? 'تم إنهاء جرد الخزينة — لا يوجد فرق'
          : variance > 0
              ? 'تم إنهاء جرد الخزينة — فائض بقيمة ${variance.toStringAsFixed(2)}'
              : 'تم إنهاء جرد الخزينة — عجز بقيمة ${variance.abs().toStringAsFixed(2)}';
      setState(() {
        _submitting = false;
        _selectedTreasury = null;
        _balanceCtrl.clear();
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(context, msg);
      _load();
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل حفظ جرد الخزينة.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);

    final variance = _variance;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<TreasuryModel>(
            initialValue: _selectedTreasury,
            decoration: const InputDecoration(labelText: 'الخزينة'),
            items: _treasuries
                .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedTreasury = v),
          ),
          if (_selectedTreasury != null) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              label: 'رصيد النظام',
              value: _selectedTreasury!.balance.toStringAsFixed(2),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _balanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الرصيد الفعلي (العد اليدوي)'),
          ),
          if (variance != null) ...[
            const SizedBox(height: 10),
            _VarianceBanner(variance: variance, decimals: 2),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.account_balance_outlined),
              label: Text(_submitting ? 'جارٍ الحفظ...' : 'تأكيد الجرد وتطبيق التسوية'),
            ),
          ),
          const SizedBox(height: 24),
          const Text('سجل الجرد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('لا توجد سجلات جرد خزائن.',
                  style: TextStyle(color: AppTheme.textMuted)),
            ),
          ..._history.map((a) => Card(
                child: ListTile(
                  title: Text(a.treasuryName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'النظام: ${a.systemBalance.toStringAsFixed(2)} — الفعلي: ${a.physicalBalance.toStringAsFixed(2)}'
                    '${a.performerName != null ? ' — بواسطة: ${a.performerName}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: _VarianceText(variance: a.variance, decimals: 2),
                ),
              )),
        ],
      ),
    );
  }
}

// ─── جرد المديونيات / جرد ديون الموردين ─────────────────────────────────
// Mirrors EntityAuditTab in JardPage.tsx — search+pick a customer/supplier,
// compare their recorded balance to a physical/paper count, submit via
// DebtAuditController (POST /debt-audits with client_type customer|supplier),
// which sets the entity's balance directly to the physical value.

class _SimpleEntity {
  final int id;
  final String name;
  final double balance;
  const _SimpleEntity({required this.id, required this.name, required this.balance});
}

class _DebtAuditTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final String clientType; // 'customer' | 'supplier'
  final String entityLabel;
  const _DebtAuditTab({
    required this.remote,
    required this.clientType,
    required this.entityLabel,
  });

  @override
  State<_DebtAuditTab> createState() => _DebtAuditTabState();
}

class _DebtAuditTabState extends State<_DebtAuditTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loadingSearch = false;
  List<_SimpleEntity> _searchResults = [];
  _SimpleEntity? _selected;

  bool _loadingHistory = true;
  String? _historyError;
  List<DebtAuditModel> _history = [];

  final _balanceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _search('');
    _balanceCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _balanceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final history = await widget.remote.fetchDebtAudits(widget.clientType);
      if (!mounted) return;
      setState(() {
        _history = history;
        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = 'فشل تحميل سجل الجرد.';
      });
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String query) async {
    setState(() => _loadingSearch = true);
    try {
      final results = widget.clientType == 'supplier'
          ? (await widget.remote.fetchSuppliers(search: query.isEmpty ? null : query))
              .data
              .map((s) => _SimpleEntity(id: s.id, name: s.name, balance: s.balance))
              .toList()
          : (await widget.remote.fetchCustomers(search: query.isEmpty ? null : query))
              .data
              .map((c) => _SimpleEntity(id: c.id, name: c.name, balance: c.balance))
              .toList();
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _loadingSearch = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSearch = false);
    }
  }

  void _selectEntity(_SimpleEntity e) {
    setState(() {
      _selected = e;
      _balanceCtrl.clear();
      _notesCtrl.clear();
    });
  }

  double? get _variance {
    final selected = _selected;
    if (selected == null) return null;
    final phys = double.tryParse(_balanceCtrl.text);
    if (phys == null) return null;
    return phys - selected.balance;
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) {
      AppSnackbar.showError(context, 'يرجى اختيار ${widget.entityLabel}.');
      return;
    }
    final phys = double.tryParse(_balanceCtrl.text);
    if (phys == null) {
      AppSnackbar.showError(context, 'أدخل الرصيد الفعلي.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final variance = await widget.remote.submitDebtAudit(
        clientType: widget.clientType,
        entityId: selected.id,
        physicalBalance: phys,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      final msg = variance.abs() < 0.001
          ? 'تم تحديث الرصيد — لا يوجد فرق'
          : 'تم تحديث الرصيد وتسجيل الجرد بنجاح';
      setState(() {
        _submitting = false;
        _selected = null;
        _balanceCtrl.clear();
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(context, msg);
      _loadHistory();
      _search(_searchCtrl.text.trim());
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل حفظ الجرد.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final variance = _variance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_selected == null) ...[
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'ابحث عن ${widget.entityLabel}',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingSearch) const Center(child: CircularProgressIndicator()),
          if (!_loadingSearch && _searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لا يوجد ${widget.entityLabel} مطابق.',
                  style: const TextStyle(color: AppTheme.textMuted)),
            ),
          ..._searchResults.map((e) => Card(
                child: ListTile(
                  title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('الرصيد الحالي: ${e.balance.toStringAsFixed(3)}',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => _selectEntity(e),
                ),
              )),
        ] else ...[
          Card(
            child: ListTile(
              title: Text(_selected!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('الرصيد الحالي بالنظام: ${_selected!.balance.toStringAsFixed(3)}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selected = null),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _balanceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الرصيد الفعلي (الجرد الورقي)'),
          ),
          if (variance != null) ...[
            const SizedBox(height: 10),
            _VarianceBanner(
              variance: variance,
              decimals: 3,
              surplusLabel: 'زيادة في الرصيد',
              shortageLabel: 'نقص في الرصيد',
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_submitting ? 'جارٍ الحفظ...' : 'تأكيد الجرد وتحديث الرصيد'),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text('سجل الجرد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (_loadingHistory) const Center(child: CircularProgressIndicator()),
        if (!_loadingHistory && _historyError != null)
          AppErrorView(message: _historyError!, onRetry: _loadHistory),
        if (!_loadingHistory && _historyError == null && _history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('لا توجد سجلات جرد.', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ..._history.map((a) => Card(
              child: ListTile(
                title: Text(a.entityName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'النظام: ${a.systemBalance.toStringAsFixed(3)} — الفعلي: ${a.physicalBalance.toStringAsFixed(3)}'
                  '${a.performerName != null ? ' — بواسطة: ${a.performerName}' : ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: _VarianceText(variance: a.variance, decimals: 3),
              ),
            )),
      ],
    );
  }
}

// ─── Shared small widgets ───────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final String label;
  final String value;
  const _InfoBanner({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.secondary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Text('$label: ', style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600)),
            Text(value,
                style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _VarianceBanner extends StatelessWidget {
  final double variance;
  final int decimals;
  final String surplusLabel;
  final String shortageLabel;
  const _VarianceBanner({
    required this.variance,
    required this.decimals,
    this.surplusLabel = 'فائض',
    this.shortageLabel = 'عجز',
  });

  @override
  Widget build(BuildContext context) {
    final threshold = decimals >= 3 ? 0.001 : 0.01;
    final absV = variance.abs();
    final isZero = absV < threshold;
    final isSurplus = variance > 0;
    final color = isZero ? AppTheme.textMuted : (isSurplus ? Colors.green.shade700 : AppTheme.danger);
    final bg = isZero
        ? Colors.grey.shade100
        : (isSurplus ? Colors.green.withValues(alpha: 0.08) : AppTheme.danger.withValues(alpha: 0.08));
    final text = isZero
        ? 'لا يوجد فرق'
        : isSurplus
            ? '$surplusLabel: +${variance.toStringAsFixed(decimals)}'
            : '$shortageLabel: ${variance.toStringAsFixed(decimals)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(
            isZero ? Icons.remove : (isSurplus ? Icons.trending_up : Icons.trending_down),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _VarianceText extends StatelessWidget {
  final double variance;
  final int decimals;
  const _VarianceText({required this.variance, required this.decimals});

  @override
  Widget build(BuildContext context) {
    final threshold = decimals >= 3 ? 0.001 : 0.01;
    final absV = variance.abs();
    if (absV < threshold) {
      return const Text('—', style: TextStyle(color: AppTheme.textMuted));
    }
    final isSurplus = variance > 0;
    return Text(
      '${isSurplus ? '+' : ''}${variance.toStringAsFixed(decimals)}',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: isSurplus ? Colors.green.shade700 : AppTheme.danger,
      ),
    );
  }
}
