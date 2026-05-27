import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/admin_models.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';

class CreateLoadingPage extends StatefulWidget {
  const CreateLoadingPage({super.key});

  @override
  State<CreateLoadingPage> createState() => _CreateLoadingPageState();
}

class _CreateLoadingPageState extends State<CreateLoadingPage> {
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();

  DelegateModel? _selectedDelegate;
  SimpleWarehouseModel? _selectedWarehouse;
  final List<_ItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(AdminLoadingFormRequested());
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final e in _items) {
      e.qtyCtrl.dispose();
    }
    super.dispose();
  }

  void _addItem(List<SimpleProductModel> products) {
    setState(() => _items.add(_ItemEntry(products: products)));
  }

  void _removeItem(int index) {
    _items[index].qtyCtrl.dispose();
    setState(() => _items.removeAt(index));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDelegate == null) {
      _showError('اختر مندوباً');
      return;
    }
    if (_selectedWarehouse == null) {
      _showError('اختر مستودعاً');
      return;
    }
    if (_items.isEmpty) {
      _showError('أضف منتجاً واحداً على الأقل');
      return;
    }
    if (_items.any((e) => e.selectedProduct == null)) {
      _showError('اختر منتجاً لكل بند');
      return;
    }

    final itemsPayload = _items
        .map((e) => {
              'product_id': e.selectedProduct!.id,
              'quantity': double.parse(e.qtyCtrl.text.trim()),
            })
        .toList();

    context.read<AdminBloc>().add(AdminLoadingSubmitted(
          delegateId: _selectedDelegate!.id,
          warehouseId: _selectedWarehouse!.id,
          items: itemsPayload,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء تحميلة جديدة')),
      body: BlocConsumer<AdminBloc, AdminState>(
        listener: (ctx, state) {
          if (state is AdminLoadingCreatedSuccess) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.secondary,
            ));
            Navigator.of(ctx).pop(true);
          }
          if (state is AdminFailure) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.danger,
            ));
          }
        },
        builder: (ctx, state) {
          if (state is AdminLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AdminFailure) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message,
                      style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ctx
                        .read<AdminBloc>()
                        .add(AdminLoadingFormRequested()),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          if (state is AdminLoadingFormLoaded) {
            return _FormBody(
              formKey: _formKey,
              state: state,
              selectedDelegate: _selectedDelegate,
              selectedWarehouse: _selectedWarehouse,
              items: _items,
              notesCtrl: _notesCtrl,
              onDelegateChanged: (d) => setState(() => _selectedDelegate = d),
              onWarehouseChanged: (w) => setState(() => _selectedWarehouse = w),
              onAddItem: () => _addItem(state.products),
              onRemoveItem: _removeItem,
              onSubmit: _submit,
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─── Form body ────────────────────────────────────────────────────────────────

class _FormBody extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final AdminLoadingFormLoaded state;
  final DelegateModel? selectedDelegate;
  final SimpleWarehouseModel? selectedWarehouse;
  final List<_ItemEntry> items;
  final TextEditingController notesCtrl;
  final ValueChanged<DelegateModel?> onDelegateChanged;
  final ValueChanged<SimpleWarehouseModel?> onWarehouseChanged;
  final VoidCallback onAddItem;
  final ValueChanged<int> onRemoveItem;
  final VoidCallback onSubmit;

  const _FormBody({
    required this.formKey,
    required this.state,
    required this.selectedDelegate,
    required this.selectedWarehouse,
    required this.items,
    required this.notesCtrl,
    required this.onDelegateChanged,
    required this.onWarehouseChanged,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Delegate picker ───────────────────────────────────────────
            _SectionHeader(title: 'المندوب', icon: Icons.person_rounded),
            const SizedBox(height: 8),
            _DelegateSearchField(
              delegates: state.delegates,
              selected: selectedDelegate,
              onSelected: onDelegateChanged,
            ),
            const SizedBox(height: 20),

            // ── Warehouse picker ──────────────────────────────────────────
            _SectionHeader(title: 'المستودع', icon: Icons.warehouse_outlined),
            const SizedBox(height: 8),
            DropdownButtonFormField<SimpleWarehouseModel>(
              value: selectedWarehouse,
              hint: const Text('اختر مستودعاً'),
              items: state.warehouses
                  .map((w) => DropdownMenuItem(
                        value: w,
                        child: Text(w.name),
                      ))
                  .toList(),
              onChanged: onWarehouseChanged,
              validator: (v) => v == null ? 'مطلوب' : null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            const SizedBox(height: 20),

            // ── Products ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _SectionHeader(
                      title: 'المنتجات', icon: Icons.inventory_2_outlined),
                ),
                TextButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('إضافة منتج'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (items.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Center(
                  child: Text('اضغط على "إضافة منتج" لإضافة بنود التحميلة',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),

            ...items.asMap().entries.map((e) => _ProductItemRow(
                  key: ValueKey(e.key),
                  index: e.key,
                  entry: e.value,
                  products: state.products,
                  onRemove: () => onRemoveItem(e.key),
                )),

            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────────────────────────
            _SectionHeader(title: 'ملاحظات', icon: Icons.notes_rounded),
            const SizedBox(height: 8),
            TextFormField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ملاحظات اختيارية...',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 28),

            // ── Submit ────────────────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.send_rounded),
                label: const Text('إرسال التحميلة',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
}

// ─── Delegate searchable field ────────────────────────────────────────────────

class _DelegateSearchField extends StatefulWidget {
  final List<DelegateModel> delegates;
  final DelegateModel? selected;
  final ValueChanged<DelegateModel?> onSelected;

  const _DelegateSearchField({
    required this.delegates,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_DelegateSearchField> createState() => _DelegateSearchFieldState();
}

class _DelegateSearchFieldState extends State<_DelegateSearchField> {
  final _ctrl = TextEditingController();
  List<DelegateModel> _filtered = [];
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.delegates;
    if (widget.selected != null) {
      _ctrl.text = widget.selected!.name;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = widget.delegates
          .where((d) =>
              d.name.contains(q) ||
              d.email.contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _ctrl,
            onTap: () => setState(() => _open = true),
            onChanged: (q) {
              _filter(q);
              setState(() => _open = true);
              if (q.isEmpty) widget.onSelected(null);
            },
            validator: (_) =>
                widget.selected == null ? 'اختر مندوباً' : null,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'ابحث عن مندوب...',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: widget.selected != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _ctrl.clear();
                        widget.onSelected(null);
                        setState(() => _open = false);
                      },
                    )
                  : const Icon(Icons.search),
            ),
          ),
          if (_open && _filtered.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: ListView(
                shrinkWrap: true,
                children: _filtered
                    .map((d) => ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: d.hasActiveShift
                                ? AppTheme.danger.withValues(alpha: 0.15)
                                : AppTheme.primary.withValues(alpha: 0.1),
                            child: Icon(Icons.person,
                                size: 16,
                                color: d.hasActiveShift
                                    ? AppTheme.danger
                                    : AppTheme.primary),
                          ),
                          title: Text(d.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: d.hasActiveShift
                              ? const Text('لديه وردية نشطة',
                                  style: TextStyle(
                                      color: AppTheme.danger, fontSize: 11))
                              : null,
                          onTap: () {
                            _ctrl.text = d.name;
                            widget.onSelected(d);
                            setState(() => _open = false);
                            FocusScope.of(context).unfocus();
                          },
                        ))
                    .toList(),
              ),
            ),
        ],
      );
}

// ─── Product item row ─────────────────────────────────────────────────────────

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
                    child: Text(
                      '${widget.index + 1}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.primary),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.danger, size: 20),
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
                          child: Text('${p.name} (${p.unit})',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (p) => setState(() => widget.entry.selectedProduct = p),
                validator: (v) => v == null ? 'اختر منتجاً' : null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: widget.entry.qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─── Section header ──────────────────────────────────────────────────────────

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
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.primary)),
        ],
      );
}

// ─── Mutable item entry ──────────────────────────────────────────────────────

class _ItemEntry {
  SimpleProductModel? selectedProduct;
  final TextEditingController qtyCtrl = TextEditingController();

  _ItemEntry({required List<SimpleProductModel> products})
      : selectedProduct = products.length == 1 ? products.first : null;
}
