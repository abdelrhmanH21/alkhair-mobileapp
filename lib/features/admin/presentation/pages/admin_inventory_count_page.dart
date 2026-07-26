import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "عملية جرد" — StocktakingController (web "جرد التصنيع"/"جرد اللبن") is
/// already warehouse-agnostic; this reuses that same create+finalize logic
/// via POST /v1/mobile/admin/inventory-count, just collapsed into one
/// mobile step instead of the web's separate draft/finalize flow.
class AdminInventoryCountPage extends StatefulWidget {
  const AdminInventoryCountPage({super.key});

  @override
  State<AdminInventoryCountPage> createState() => _AdminInventoryCountPageState();
}

class _AdminInventoryCountPageState extends State<AdminInventoryCountPage> {
  final _remote = sl<AdminRemoteDataSource>();

  bool _loadingWarehouses = true;
  List<SimpleWarehouseModel> _warehouses = [];
  List<TreasuryModel> _treasuries = [];
  List<CustomerModel> _customers = [];

  int? _warehouseId;
  bool _loadingItems = false;
  List<InventoryCountItemModel> _items = [];
  final Map<String, TextEditingController> _counts = {};

  String _settlementType = 'none';
  int? _treasuryId;
  int? _customerId;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  String _keyFor(InventoryCountItemModel item) =>
      item.itemType == 'product' ? 'p${item.productId}' : 'r${item.rawMaterialId}';

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
    setState(() => _loadingWarehouses = true);
    try {
      final warehouses = await _remote.fetchWarehouses();
      setState(() {
        _warehouses = warehouses;
        _loadingWarehouses = false;
      });
    } catch (_) {
      setState(() => _loadingWarehouses = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل المخازن.');
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
    setState(() => _loadingItems = true);
    try {
      final items = await _remote.fetchInventoryCountItems(warehouseId);
      setState(() {
        _items = items;
        for (final item in items) {
          _counts[_keyFor(item)] = TextEditingController();
        }
        _loadingItems = false;
      });
    } catch (_) {
      setState(() => _loadingItems = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل أصناف المخزن.');
    }
  }

  Future<void> _loadSettlementRefData() async {
    if (_treasuries.isNotEmpty || _customers.isNotEmpty) return;
    try {
      final results = await Future.wait([
        _remote.fetchTreasuries(),
        _remote.fetchCustomers(),
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
        if (item.itemType == 'product') 'product_id': item.productId else 'raw_material_id': item.rawMaterialId,
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
      final variance = await _remote.submitInventoryCount(
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
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل إنهاء الجرد.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عملية جرد')),
      body: _loadingWarehouses
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                  onChanged: _onWarehouseChanged,
                ),
                const SizedBox(height: 16),
                if (_loadingItems) const Center(child: CircularProgressIndicator()),
                if (!_loadingItems && _warehouseId != null && _items.isEmpty)
                  const Text('لا توجد أصناف في هذا المخزن.', style: TextStyle(color: AppTheme.textMuted)),
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('النظام: ${item.systemQuantity.toStringAsFixed(2)} ${item.unit}',
                                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _counts[_keyFor(item)],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(labelText: 'الفعلي', isDense: true),
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
                      items: _treasuries.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                      onChanged: (v) => setState(() => _treasuryId = v),
                    ),
                  if (_settlementType == 'customer')
                    DropdownButtonFormField<int>(
                      initialValue: _customerId,
                      decoration: const InputDecoration(labelText: 'العميل'),
                      items: _customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
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
            ),
    );
  }
}
