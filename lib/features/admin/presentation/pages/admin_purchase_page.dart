import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

class _PurchaseLineItem {
  final bool isRawMaterial;
  final int? rawMaterialId;
  final int? productId;
  final int? warehouseId;
  final String name;
  final String unit;
  double quantity;
  double unitPrice;
  final double discount = 0;
  _PurchaseLineItem({
    required this.isRawMaterial,
    this.rawMaterialId,
    this.productId,
    this.warehouseId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });
  double get total => (quantity * unitPrice - discount).clamp(0, double.infinity);
}

/// "عملية شراء" — submits to POST /v1/mobile/admin/purchase, which mirrors
/// PurchaseController::store() on the web exactly (same Purchase/PurchaseItem
/// models), so purchases recorded here show up identically in the web
/// "المشتريات" screen.
class AdminPurchasePage extends StatefulWidget {
  const AdminPurchasePage({super.key});

  @override
  State<AdminPurchasePage> createState() => _AdminPurchasePageState();
}

class _AdminPurchasePageState extends State<AdminPurchasePage> {
  final _remote = sl<AdminRemoteDataSource>();

  bool _loadingRefData = true;
  List<SupplierModel> _suppliers = [];
  List<IdNameModel> _labs = [];
  List<TreasuryModel> _treasuries = [];
  List<RawMaterialModel> _rawMaterials = [];
  List<SimpleProductModel> _products = [];
  List<SimpleWarehouseModel> _warehouses = [];

  int? _supplierId;
  int? _labId;
  int? _treasuryId;
  DateTime _purchaseDate = DateTime.now();
  final _paidCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<_PurchaseLineItem> _items = [];
  bool _submitting = false;

  double get _total => _items.fold(0.0, (s, i) => s + i.total);

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() => _loadingRefData = true);
    try {
      final results = await Future.wait([
        _remote.fetchSuppliers(),
        _remote.fetchLabs(),
        _remote.fetchTreasuries(),
        _remote.fetchRawMaterials(),
        _remote.fetchProducts(),
        _remote.fetchWarehouses(),
      ]);
      setState(() {
        _suppliers = (results[0] as SupplierPageModel).data;
        _labs = results[1] as List<IdNameModel>;
        _treasuries = results[2] as List<TreasuryModel>;
        _rawMaterials = results[3] as List<RawMaterialModel>;
        _products = results[4] as List<SimpleProductModel>;
        _warehouses = results[5] as List<SimpleWarehouseModel>;
        _treasuryId = _treasuries.where((t) => t.isDefault).map((t) => t.id).firstOrNull ??
            (_treasuries.isNotEmpty ? _treasuries.first.id : null);
        _loadingRefData = false;
      });
    } catch (_) {
      setState(() => _loadingRefData = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل بيانات الشاشة.');
    }
  }

  void _openAddItemSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PurchaseItemPickerSheet(
        rawMaterials: _rawMaterials,
        products: _products,
        warehouses: _warehouses,
        onAdd: (item) => setState(() => _items.add(item)),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
  }

  Future<void> _submit() async {
    if (_items.isEmpty) {
      AppSnackbar.showError(context, 'يرجى إضافة صنف واحد على الأقل.');
      return;
    }
    if (_treasuryId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة.');
      return;
    }
    final paid = double.tryParse(_paidCtrl.text) ?? 0;

    setState(() => _submitting = true);
    try {
      await _remote.submitPurchase(
        supplierId: _supplierId,
        labId: _labId,
        treasuryId: _treasuryId!,
        purchaseDate: DateFormat('yyyy-MM-dd').format(_purchaseDate),
        paidAmount: paid,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: _items
            .map((i) => {
                  if (i.isRawMaterial) 'raw_material_id': i.rawMaterialId else 'product_id': i.productId,
                  if (!i.isRawMaterial) 'warehouse_id': i.warehouseId,
                  'quantity': i.quantity,
                  'unit_price': i.unitPrice,
                  'discount': i.discount,
                })
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _supplierId = null;
        _labId = null;
        _items.clear();
        _paidCtrl.clear();
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(context, 'تم حفظ فاتورة الشراء بنجاح.');
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل حفظ فاتورة الشراء.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عملية شراء')),
      body: _loadingRefData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _supplierId,
                  decoration: const InputDecoration(labelText: 'المورد (اختياري)'),
                  items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) => setState(() => _supplierId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _labId,
                  decoration: const InputDecoration(labelText: 'المعمل (اختياري)'),
                  items: _labs.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
                  onChanged: (v) => setState(() => _labId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _treasuryId,
                  decoration: const InputDecoration(labelText: 'الخزينة'),
                  items: _treasuries.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (v) => setState(() => _treasuryId = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(DateFormat('yyyy-MM-dd').format(_purchaseDate)),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.inventory_outlined, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 4),
                            const Text('الأصناف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                              onPressed: _openAddItemSheet,
                            ),
                          ],
                        ),
                        if (_items.isEmpty)
                          const Center(child: Text('لا توجد أصناف', style: TextStyle(color: Colors.grey)))
                        else
                          ..._items.asMap().entries.map((e) => ListTile(
                                dense: true,
                                title: Text(e.value.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text(
                                    '${e.value.quantity} ${e.value.unit} × ${e.value.unitPrice.toStringAsFixed(2)} = ${e.value.total.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.danger),
                                  onPressed: () => setState(() => _items.removeAt(e.key)),
                                ),
                              )),
                        const Divider(),
                        Text('الإجمالي: ${_total.toStringAsFixed(2)}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _paidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'المبلغ المدفوع', hintText: '0'),
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
                        : const Icon(Icons.send_rounded),
                    label: Text(_submitting ? 'جارٍ الحفظ...' : 'حفظ فاتورة الشراء'),
                  ),
                ),
              ],
            ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _PurchaseItemPickerSheet extends StatefulWidget {
  final List<RawMaterialModel> rawMaterials;
  final List<SimpleProductModel> products;
  final List<SimpleWarehouseModel> warehouses;
  final void Function(_PurchaseLineItem) onAdd;
  const _PurchaseItemPickerSheet({
    required this.rawMaterials,
    required this.products,
    required this.warehouses,
    required this.onAdd,
  });

  @override
  State<_PurchaseItemPickerSheet> createState() => _PurchaseItemPickerSheetState();
}

class _PurchaseItemPickerSheetState extends State<_PurchaseItemPickerSheet>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  RawMaterialModel? _selectedRm;
  SimpleProductModel? _selectedProduct;
  int? _warehouseId;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _tabController.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _confirmAdd() {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    if (qty <= 0 || price < 0) return;

    if (_tabController.index == 0) {
      final rm = _selectedRm;
      if (rm == null) return;
      widget.onAdd(_PurchaseLineItem(
        isRawMaterial: true,
        rawMaterialId: rm.id,
        name: rm.name,
        unit: rm.unit,
        quantity: qty,
        unitPrice: price,
      ));
    } else {
      final p = _selectedProduct;
      if (p == null || _warehouseId == null) {
        AppSnackbar.showError(context, 'يرجى اختيار المنتج والمخزن.');
        return;
      }
      widget.onAdd(_PurchaseLineItem(
        isRawMaterial: false,
        productId: p.id,
        warehouseId: _warehouseId,
        name: p.name,
        unit: p.unit,
        quantity: qty,
        unitPrice: price,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 8,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(controller: _tabController, tabs: const [Tab(text: 'مادة خام'), Tab(text: 'منتج تام')]),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ListView.separated(
                    itemCount: widget.rawMaterials.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final rm = widget.rawMaterials[i];
                      return ListTile(
                        selected: _selectedRm?.id == rm.id,
                        title: Text(rm.name),
                        subtitle: Text('${rm.unit} — متاح: ${rm.currentStock.toStringAsFixed(2)}'),
                        onTap: () => setState(() {
                          _selectedRm = rm;
                          _priceCtrl.text = rm.costPrice.toStringAsFixed(2);
                        }),
                      );
                    },
                  ),
                  ListView.separated(
                    itemCount: widget.products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = widget.products[i];
                      return ListTile(
                        selected: _selectedProduct?.id == p.id,
                        title: Text(p.name),
                        subtitle: Text(p.unit),
                        onTap: () => setState(() {
                          _selectedProduct = p;
                          _priceCtrl.text = p.salePrice.toStringAsFixed(2);
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_tabController.index == 1 && _selectedProduct != null) ...[
              DropdownButtonFormField<int>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(labelText: 'المخزن', isDense: true),
                items: widget.warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
              const SizedBox(height: 8),
            ],
            if (_selectedRm != null || _selectedProduct != null) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'الكمية', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'سعر الوحدة', isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _confirmAdd, child: const Text('إضافة')),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
