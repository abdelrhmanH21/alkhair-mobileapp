import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "إضافة منتجات لتحميلة نشطة" (Part 5) — a mid-shift top-up to a delegate's
/// already-accepted/in_transit loading, distinct from [CreateLoadingPage]'s
/// one-shot "start a new loading" flow. Calls AdminRemoteDataSource
/// directly rather than going through AdminBloc (same "page pushed over an
/// already-mounted bloc screen" convention used by admin_sale_page.dart and
/// the other admin operation screens reached from these same menus) — the
/// submitted items only ever become real truck stock once the delegate
/// confirms via the pending-addition prompt on their own home screen (see
/// DelegateLoadingController::confirmAddition()), never immediately here.
class AddLoadingItemsPage extends StatefulWidget {
  const AddLoadingItemsPage({super.key});

  @override
  State<AddLoadingItemsPage> createState() => _AddLoadingItemsPageState();
}

class _AddLoadingItemsPageState extends State<AddLoadingItemsPage> {
  final _remote = sl<AdminRemoteDataSource>();
  final _formKey = GlobalKey<FormState>();

  List<DelegateModel> _eligibleDelegates = [];
  List<SimpleProductModel> _products = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  DelegateModel? _selectedDelegate;
  final List<_ItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final e in _items) {
      e.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _remote.fetchDelegates(),
        _remote.fetchProducts(),
      ]);
      final delegates = results[0] as List<DelegateModel>;
      final products = results[1] as List<SimpleProductModel>;
      if (!mounted) return;
      setState(() {
        // Only a loading that's actively being sold from can be topped up —
        // matches addItems()'s own accepted/in_transit gate server-side;
        // filtering here just avoids offering a delegate the request would
        // reject anyway (pending_pickup has no confirmed shift yet,
        // completed/settled/idle have nothing left to add to).
        _eligibleDelegates = delegates
            .where((d) =>
                d.activeLoadingId != null &&
                (d.loadingStatus == 'accepted' || d.loadingStatus == 'in_transit'))
            .toList();
        _products = products;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'فشل تحميل البيانات.';
        });
      }
    }
  }

  void _addItem() {
    setState(() => _items.add(_ItemEntry(products: _products)));
  }

  void _removeItem(int index) {
    _items[index].qtyCtrl.dispose();
    setState(() => _items.removeAt(index));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final delegate = _selectedDelegate;
    if (delegate == null || delegate.activeLoadingId == null) {
      AppSnackbar.showError(context, 'اختر مندوباً لديه تحميلة نشطة');
      return;
    }
    if (_items.isEmpty) {
      AppSnackbar.showError(context, 'أضف منتجاً واحداً على الأقل');
      return;
    }
    if (_items.any((e) => e.selectedProduct == null)) {
      AppSnackbar.showError(context, 'اختر منتجاً لكل بند');
      return;
    }

    final itemsPayload = _items
        .map((e) => {
              'product_id': e.selectedProduct!.id,
              'quantity': double.parse(e.qtyCtrl.text.trim()),
            })
        .toList();

    setState(() => _submitting = true);
    try {
      await _remote.addLoadingItems(
        loadingId: delegate.activeLoadingId!,
        items: itemsPayload,
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(context, 'تم إرسال المنتجات الإضافية، بانتظار تأكيد المندوب.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'تعذر إضافة المنتجات. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة منتجات لتحميلة نشطة')),
      body: _build(),
    );
  }

  Widget _build() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: 'المندوب (تحميلة نشطة فقط)', icon: Icons.person_rounded),
          const SizedBox(height: 8),
          if (_eligibleDelegates.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(
                child: Text('لا يوجد مناديب لديهم تحميلة نشطة (مستلمة أو في الطريق) حالياً.',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            )
          else
            DropdownButtonFormField<DelegateModel>(
              value: _selectedDelegate,
              hint: const Text('اختر مندوباً'),
              isExpanded: true,
              items: _eligibleDelegates
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text('${d.name} — تحميلة #${d.activeLoadingId}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (d) => setState(() => _selectedDelegate = d),
              validator: (v) => v == null ? 'اختر مندوباً' : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          const SizedBox(height: 20),

          Row(
            children: [
              const Expanded(
                child: _SectionHeader(title: 'المنتجات الإضافية', icon: Icons.inventory_2_outlined),
              ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('إضافة منتج'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(
                child: Text('اضغط على "إضافة منتج" لإضافة البنود الإضافية',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            ),

          ..._items.asMap().entries.map((e) => _ProductItemRow(
                key: ValueKey(e.key),
                index: e.key,
                entry: e.value,
                products: _products,
                onRemove: () => _removeItem(e.key),
              )),

          const SizedBox(height: 28),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: const Text('إرسال المنتجات الإضافية', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primary)),
        ],
      );
}

class _ProductItemRow extends StatefulWidget {
  final int index;
  final _ItemEntry entry;
  final List<SimpleProductModel> products;
  final VoidCallback onRemove;

  const _ProductItemRow({
    super.key,
    required this.index,
    required this.entry,
    required this.products,
    required this.onRemove,
  });

  @override
  State<_ProductItemRow> createState() => _ProductItemRowState();
}

class _ProductItemRowState extends State<_ProductItemRow> {
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: Text('${widget.index + 1}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SimpleProductModel>(
                value: widget.entry.selectedProduct,
                hint: const Text('اختر منتجاً'),
                isExpanded: true,
                items: widget.products
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text('${p.name} (${p.unit})', overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (p) => setState(() => widget.entry.selectedProduct = p),
                validator: (v) => v == null ? 'اختر منتجاً' : null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.entry.qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'أدخل الكمية';
                  final qty = double.tryParse(v);
                  if (qty == null || qty <= 0) return 'كمية غير صحيحة';
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'الكمية',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ItemEntry {
  SimpleProductModel? selectedProduct;
  final TextEditingController qtyCtrl = TextEditingController();

  _ItemEntry({required List<SimpleProductModel> products});
}
