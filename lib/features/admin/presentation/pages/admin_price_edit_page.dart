import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "تعديل سعر" — pick a product (wholesale price) or a raw material (cost
/// price) from a searchable list, confirm the change, submit to
/// PUT /v1/mobile/admin/products/{id}/price or
/// PUT /v1/mobile/admin/raw-materials/{id}/price.
class AdminPriceEditPage extends StatefulWidget {
  const AdminPriceEditPage({super.key});

  @override
  State<AdminPriceEditPage> createState() => _AdminPriceEditPageState();
}

class _AdminPriceEditPageState extends State<AdminPriceEditPage>
    with SingleTickerProviderStateMixin {
  final _remote = sl<AdminRemoteDataSource>();
  late final _tabController = TabController(length: 2, vsync: this);

  List<SimpleProductModel> _products = [];
  List<RawMaterialModel> _rawMaterials = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _remote.fetchProducts(),
        _remote.fetchRawMaterials(),
      ]);
      setState(() {
        _products = results[0] as List<SimpleProductModel>;
        _rawMaterials = results[1] as List<RawMaterialModel>;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'فشل تحميل البيانات.';
      });
    }
  }

  Future<void> _editProductPrice(SimpleProductModel product) async {
    final newPrice = await _promptNewPrice(product.name, product.salePrice);
    if (newPrice == null) return;
    final confirmed =
        await _confirmChange(product.name, product.salePrice, newPrice);
    if (confirmed != true) return;
    try {
      final result = await _remote.updateProductPrice(product.id, newPrice);
      if (!mounted) return;
      AppSnackbar.showSuccess(context,
          'تم تغيير سعر ${result.name} من ${result.oldPrice.toStringAsFixed(2)} إلى ${result.newPrice.toStringAsFixed(2)}');
      _load();
    } on DioException catch (e) {
      if (mounted) {
        AppSnackbar.showError(context,
            e.response?.data?['message'] as String? ?? 'فشل تحديث السعر.');
      }
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  Future<void> _editRawMaterialPrice(RawMaterialModel material) async {
    final newPrice = await _promptNewPrice(material.name, material.costPrice);
    if (newPrice == null) return;
    final confirmed =
        await _confirmChange(material.name, material.costPrice, newPrice);
    if (confirmed != true) return;
    try {
      final result =
          await _remote.updateRawMaterialPrice(material.id, newPrice);
      if (!mounted) return;
      AppSnackbar.showSuccess(context,
          'تم تغيير سعر ${result.name} من ${result.oldPrice.toStringAsFixed(2)} إلى ${result.newPrice.toStringAsFixed(2)}');
      _load();
    } on DioException catch (e) {
      if (mounted) {
        AppSnackbar.showError(context,
            e.response?.data?['message'] as String? ?? 'فشل تحديث السعر.');
      }
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  Future<double?> _promptNewPrice(String name, double currentPrice) async {
    final ctrl = TextEditingController(text: currentPrice.toStringAsFixed(2));
    return showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('السعر الحالي: ${currentPrice.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'السعر الجديد'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final price = double.tryParse(ctrl.text);
              if (price == null || price < 0) {
                AppSnackbar.showError(dialogCtx, 'يرجى إدخال سعر صحيح.');
                return;
              }
              Navigator.pop(dialogCtx, price);
            },
            child: const Text('التالي'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmChange(String name, double oldPrice, double newPrice) {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تأكيد تغيير السعر'),
        content: Text(
            'هل تريد تغيير سعر "$name" من ${oldPrice.toStringAsFixed(2)} إلى ${newPrice.toStringAsFixed(2)}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _products
        .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    final filteredMaterials = _rawMaterials
        .where((m) => m.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل سعر'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [Tab(text: 'منتجات'), Tab(text: 'مواد خام')],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم...', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: AppErrorView(message: _error!, onRetry: _load))
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ProductList(
                      products: filteredProducts, onTap: _editProductPrice),
                  _RawMaterialList(
                      materials: filteredMaterials,
                      onTap: _editRawMaterialPrice),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  final List<SimpleProductModel> products;
  final void Function(SimpleProductModel) onTap;
  const _ProductList({required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
          child: Text('لا توجد منتجات',
              style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading:
                const Icon(Icons.inventory_outlined, color: AppTheme.primary),
            title: Text(p.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'سعر الجملة الحالي: ${p.salePrice.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12)),
            trailing:
                const Icon(Icons.edit_outlined, color: AppTheme.secondary),
            onTap: () => onTap(p),
          ),
        );
      },
    );
  }
}

class _RawMaterialList extends StatelessWidget {
  final List<RawMaterialModel> materials;
  final void Function(RawMaterialModel) onTap;
  const _RawMaterialList({required this.materials, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) {
      return const Center(
          child: Text('لا توجد مواد خام',
              style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: materials.length,
      itemBuilder: (_, i) {
        final m = materials[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.science_outlined, color: AppTheme.accent),
            title: Text(m.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                'سعر التكلفة الحالي: ${m.costPrice.toStringAsFixed(2)} / ${m.unit}',
                style: const TextStyle(fontSize: 12)),
            trailing:
                const Icon(Icons.edit_outlined, color: AppTheme.secondary),
            onTap: () => onTap(m),
          ),
        );
      },
    );
  }
}
