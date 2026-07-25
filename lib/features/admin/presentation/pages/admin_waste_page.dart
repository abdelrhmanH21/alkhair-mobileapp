import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "تسجيل هالك" — submits to POST /v1/mobile/admin/waste (new WasteRecord
/// model on the backend). Deducts the entered quantity directly from the
/// product/raw-material stock in the chosen warehouse, same locking/
/// negative-stock-guard pattern InventoryController::adjust() already uses.
class AdminWastePage extends StatefulWidget {
  const AdminWastePage({super.key});

  @override
  State<AdminWastePage> createState() => _AdminWastePageState();
}

class _AdminWastePageState extends State<AdminWastePage> {
  final _remote = sl<AdminRemoteDataSource>();

  bool _loadingRefData = true;
  List<SimpleProductModel> _products = [];
  List<RawMaterialModel> _rawMaterials = [];
  List<SimpleWarehouseModel> _warehouses = [];

  String _itemType = 'product';
  int? _productId;
  int? _rawMaterialId;
  int? _warehouseId;
  final _qtyCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() => _loadingRefData = true);
    try {
      final results = await Future.wait([
        _remote.fetchProducts(),
        _remote.fetchRawMaterials(),
        _remote.fetchWarehouses(),
      ]);
      setState(() {
        _products = results[0] as List<SimpleProductModel>;
        _rawMaterials = results[1] as List<RawMaterialModel>;
        _warehouses = results[2] as List<SimpleWarehouseModel>;
        _loadingRefData = false;
      });
    } catch (_) {
      setState(() => _loadingRefData = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل بيانات الشاشة.');
    }
  }

  Future<void> _submit() async {
    if (_itemType == 'product' && _productId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المنتج.');
      return;
    }
    if (_itemType == 'raw_material' && _rawMaterialId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المادة الخام.');
      return;
    }
    if (_warehouseId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المخزن.');
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text);
    if (qty == null || qty <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال كمية صحيحة.');
      return;
    }
    if (_reasonCtrl.text.trim().isEmpty) {
      AppSnackbar.showError(context, 'يرجى إدخال سبب الهالك.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _remote.submitWaste(
        itemType: _itemType,
        productId: _itemType == 'product' ? _productId : null,
        rawMaterialId: _itemType == 'raw_material' ? _rawMaterialId : null,
        warehouseId: _warehouseId!,
        quantity: qty,
        reason: _reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _productId = null;
        _rawMaterialId = null;
        _qtyCtrl.clear();
        _reasonCtrl.clear();
      });
      AppSnackbar.showSuccess(context, 'تم تسجيل الهالك وخصمه من المخزون.');
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل تسجيل الهالك.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل هالك')),
      body: _loadingRefData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('منتج تام'),
                        selected: _itemType == 'product',
                        onSelected: (_) => setState(() {
                          _itemType = 'product';
                          _rawMaterialId = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('مادة خام'),
                        selected: _itemType == 'raw_material',
                        selectedColor: AppTheme.accent.withValues(alpha: 0.3),
                        onSelected: (_) => setState(() {
                          _itemType = 'raw_material';
                          _productId = null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_itemType == 'product')
                  DropdownButtonFormField<int>(
                    initialValue: _productId,
                    decoration: const InputDecoration(labelText: 'المنتج'),
                    items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (v) => setState(() => _productId = v),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: _rawMaterialId,
                    decoration: const InputDecoration(labelText: 'المادة الخام'),
                    items: _rawMaterials
                        .map((m) => DropdownMenuItem(
                            value: m.id, child: Text('${m.name} (متاح: ${m.currentStock.toStringAsFixed(2)})')))
                        .toList(),
                    onChanged: (v) => setState(() => _rawMaterialId = v),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'المخزن'),
                  items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية', hintText: '0'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(labelText: 'السبب', hintText: 'مثال: تلف أثناء النقل'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.delete_outline),
                    label: Text(_submitting ? 'جارٍ الحفظ...' : 'تسجيل الهالك'),
                  ),
                ),
              ],
            ),
    );
  }
}
