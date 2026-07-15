import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/client_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/sellable_product_model.dart';
import '../../data/models/catalog_product_model.dart';
// ignore: unused_import
import '../widgets/add_client_sheet.dart';
import '../widgets/client_search_field.dart';
import 'invoice_history_page.dart';
import 'truck_stock_page.dart';
import 'print_invoice_page.dart';
import 'dashboard_page.dart';

class InvoicePage extends StatefulWidget {
  const InvoicePage({super.key});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  // ── Client selection ───────────────────────────────────────────────────────
  ClientModel? _selectedClient;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<ClientModel> _searchResults = [];
  bool _searchLoading = false;

  void _onSearchFocusChanged() {
    // Opening the search field with no query yet shows the full, browsable
    // client list instead of nothing until the delegate starts typing.
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) {
      setState(() => _searchLoading = true);
      context.read<DelegateBloc>().add(DelegateClientSearchRequested(''));
    }
  }

  // ── Sales line items ───────────────────────────────────────────────────────
  final List<InvoiceSaleItem> _salesItems = [];

  // ── Return line items ──────────────────────────────────────────────────────
  final List<InvoiceReturnItem> _returnItems = [];

  // ── Cash received ──────────────────────────────────────────────────────────
  final _cashCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _cashCtrl.dispose();
    super.dispose();
  }

  double get _grossSales =>
      _salesItems.fold(0.0, (s, i) => s + i.subtotal);

  double get _totalReturns =>
      _returnItems.fold(0.0, (s, i) => s + i.subtotal);

  double get _netTotal => _grossSales - _totalReturns;

  double get _cashReceived => double.tryParse(_cashCtrl.text) ?? 0;

  double get _remainingDebt => (_netTotal - _cashReceived).clamp(0, double.infinity);

  void _submitInvoice() {
    if (_selectedClient == null) {
      _showError('يرجى اختيار عميل أولاً.');
      return;
    }
    if (_salesItems.isEmpty && _returnItems.isEmpty) {
      _showError('يرجى إضافة مبيعات أو مرتجعات.');
      return;
    }
    for (final s in _salesItems) {
      if (s.quantity <= 0 || s.unitPrice < 0) {
        _showError('تحقق من الكميات والأسعار في المبيعات.');
        return;
      }
    }

    context.read<DelegateBloc>().add(DelegateInvoiceSubmitted(
          clientId: _selectedClient!.id,
          salesItems: _salesItems,
          returnedItems: _returnItems,
          cashReceived: _cashReceived,
        ));
  }

  void _showError(String msg) {
    AppSnackbar.showError(context, msg);
  }

  void _openAddClientSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: AddClientSheet(
          onClientAdded: (client) => setState(() {
            _selectedClient = client;
            _searchCtrl.text = client.name;
            _searchResults.clear();
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فاتورة جديدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'سجل الفواتير',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => BlocProvider.value(
                      value: context.read<DelegateBloc>(),
                      child: const InvoiceHistoryPage(),
                    ))),
          ),
          IconButton(
            icon: const Icon(Icons.inventory_rounded),
            tooltip: 'مخزون الشاحنة',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => BlocProvider.value(
                      value: context.read<DelegateBloc>(),
                      child: const TruckStockPage(),
                    ))),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: 'لوحة الأداء',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => BlocProvider.value(
                      value: context.read<DelegateBloc>(),
                      child: const DashboardPage(),
                    ))),
          ),
        ],
      ),
      body: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateClientSearchResults) {
            setState(() {
              _searchResults = state.clients;
              _searchLoading = false;
            });
          }
          if (state is DelegateInvoiceSubmittedState) {
            final invoice = state.invoice;
            // Reset form
            setState(() {
              _selectedClient = null;
              _salesItems.clear();
              _returnItems.clear();
              _cashCtrl.clear();
              _searchCtrl.clear();
              _searchResults.clear();
            });
            AppSnackbar.showSuccess(
              ctx,
              invoice.debtReduction > 0
                  ? 'تم حفظ الفاتورة بنجاح — تم سداد ${invoice.debtReduction.toStringAsFixed(2)} جنيه من دين العميل السابق.'
                  : 'تم حفظ الفاتورة بنجاح',
            );
            // Offer print
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => PrintInvoicePage(invoiceId: invoice.id),
              ),
            );
          }
          if (state is DelegateFailure) {
            setState(() => _searchLoading = false);
            _showError(state.message);
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClientSearchField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                results: _searchResults,
                isLoading: _searchLoading,
                selectedClient: _selectedClient,
                onSearch: (q) {
                  setState(() => _searchLoading = true);
                  context.read<DelegateBloc>().add(DelegateClientSearchRequested(q));
                },
                onSelect: (c) => setState(() {
                  _selectedClient = c;
                  _searchCtrl.text = c.name;
                  _searchResults.clear();
                }),
                onAddNew: _openAddClientSheet,
              ),
              const SizedBox(height: 16),

              // ── Transaction Matrix ──────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SalesSection(
                      items: _salesItems,
                      clientId: _selectedClient?.id,
                      onChange: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ReturnsSection(
                      items: _returnItems,
                      onChange: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Live Totals Card ────────────────────────────────────────────
              _TotalsCard(
                grossSales: _grossSales,
                totalReturns: _totalReturns,
                netTotal: _netTotal,
                cashCtrl: _cashCtrl,
                remainingDebt: _remainingDebt,
                onCashChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),

              BlocBuilder<DelegateBloc, DelegateState>(
                builder: (_, state) => SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: state is DelegateLoading ? null : _submitInvoice,
                    icon: state is DelegateLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(state is DelegateLoading ? 'جارٍ الحفظ...' : 'إصدار الفاتورة'),
                    style: ElevatedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 17)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sales Section ─────────────────────────────────────────────────────────────

class _SalesSection extends StatelessWidget {
  final List<InvoiceSaleItem> items;
  final int? clientId;
  final VoidCallback onChange;
  const _SalesSection({required this.items, required this.clientId, required this.onChange});

  void _addItem(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _SellableProductPickerSheet(
          clientId: clientId,
          onAdd: (item) {
            items.add(item);
            onChange();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 4),
                  const Text('المبيعات',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppTheme.primary),
                    onPressed: () => _addItem(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const Center(
                    child: Text('لا توجد بنود',
                        style: TextStyle(color: Colors.grey, fontSize: 12)))
              else
                ...items.asMap().entries.map((e) => _SaleItemRow(
                      item: e.value,
                      index: e.key,
                      onRemove: () {
                        items.removeAt(e.key);
                        onChange();
                      },
                      onChange: onChange,
                    )),
              const Divider(),
              Text(
                'الإجمالي: ${items.fold(0.0, (s, i) => s + i.subtotal).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.primary),
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
      );
}

class _SaleItemRow extends StatelessWidget {
  final InvoiceSaleItem item;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onChange;
  const _SaleItemRow(
      {required this.item,
      required this.index,
      required this.onRemove,
      required this.onChange});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(item.productName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      size: 18, color: AppTheme.danger),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _SmallNumberField(
                    label: item.maxQty.isFinite ? 'كمية (حتى ${item.maxQty.toStringAsFixed(0)})' : 'كمية',
                    initialValue: item.quantity.toString(),
                    onChanged: (v) {
                      final qty = double.tryParse(v) ?? 0;
                      item.quantity = qty.clamp(0, item.maxQty);
                      onChange();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _ReadOnlyPriceField(price: item.unitPrice),
                ),
              ],
            ),
            Text(
              '= ${item.subtotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
}

// ─── Returns Section ───────────────────────────────────────────────────────────

class _ReturnsSection extends StatelessWidget {
  final List<InvoiceReturnItem> items;
  final VoidCallback onChange;
  const _ReturnsSection({required this.items, required this.onChange});

  void _addItem(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _ReturnProductPickerSheet(onAdd: (item) {
          items.add(item);
          onChange();
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_return_outlined,
                      color: AppTheme.accent, size: 18),
                  const SizedBox(width: 4),
                  const Text('المرتجعات',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppTheme.accent),
                    onPressed: () => _addItem(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const Center(
                    child: Text('لا توجد مرتجعات',
                        style: TextStyle(color: Colors.grey, fontSize: 12)))
              else
                ...items.asMap().entries.map((e) => _ReturnItemRow(
                      item: e.value,
                      index: e.key,
                      onRemove: () {
                        items.removeAt(e.key);
                        onChange();
                      },
                      onChange: onChange,
                    )),
              const Divider(),
              Text(
                'الإجمالي: -${items.fold(0.0, (s, i) => s + i.subtotal).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppTheme.accent),
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ),
      );
}

class _ReturnItemRow extends StatefulWidget {
  final InvoiceReturnItem item;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onChange;
  const _ReturnItemRow(
      {required this.item,
      required this.index,
      required this.onRemove,
      required this.onChange});

  @override
  State<_ReturnItemRow> createState() => _ReturnItemRowState();
}

class _ReturnItemRowState extends State<_ReturnItemRow> {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(widget.item.productName,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline,
                      size: 18, color: AppTheme.danger),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _SmallNumberField(
                    label: 'كمية',
                    initialValue: widget.item.quantity.toString(),
                    onChanged: (v) {
                      widget.item.quantity = double.tryParse(v) ?? 0;
                      widget.onChange();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _ReadOnlyPriceField(price: widget.item.unitPrice),
                ),
              ],
            ),
            // Condition toggle
            Row(
              children: [
                const Text('الحالة:', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('سليم', style: TextStyle(fontSize: 11)),
                  selected: widget.item.condition == 'سليم',
                  onSelected: (_) {
                    setState(() => widget.item.condition = 'سليم');
                    widget.onChange();
                  },
                  selectedColor: AppTheme.secondary.withValues(alpha: 0.3),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('تالف', style: TextStyle(fontSize: 11)),
                  selected: widget.item.condition == 'تالف',
                  onSelected: (_) {
                    setState(() => widget.item.condition = 'تالف');
                    widget.onChange();
                  },
                  selectedColor: AppTheme.danger.withValues(alpha: 0.3),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      );
}

// ─── Totals Card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  final double grossSales;
  final double totalReturns;
  final double netTotal;
  final TextEditingController cashCtrl;
  final double remainingDebt;
  final VoidCallback onCashChanged;

  const _TotalsCard({
    required this.grossSales,
    required this.totalReturns,
    required this.netTotal,
    required this.cashCtrl,
    required this.remainingDebt,
    required this.onCashChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _TotalRow('إجمالي المبيعات', grossSales, AppTheme.primary),
              _TotalRow('إجمالي المرتجعات', -totalReturns, AppTheme.accent),
              const Divider(thickness: 2),
              _TotalRow('الصافي', netTotal, AppTheme.primary, bold: true),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('نقداً مستلم:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: cashCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '0',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => onCashChanged(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (remainingDebt > 0)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('يُضاف للدين:',
                          style: TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.bold)),
                      Text(
                        remainingDebt.toStringAsFixed(2),
                        style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool bold;
  const _TotalRow(this.label, this.value, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    fontSize: bold ? 15 : 13)),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  fontSize: bold ? 17 : 14),
            ),
          ],
        ),
      );
}

// ─── Sellable-products picker (sales) ──────────────────────────────────────────
//
// Sourced ONLY from GET /delegate/sellable-products (the delegate's actual
// truck stock, with server-resolved prices). Never free-typed — see the
// backend fix in DelegateLoadingController::sellableProducts /
// DelegateInvoiceController::store on the alkhair-erp repo.

class _SellableProductPickerSheet extends StatefulWidget {
  final int? clientId;
  final void Function(InvoiceSaleItem) onAdd;
  const _SellableProductPickerSheet({required this.clientId, required this.onAdd});

  @override
  State<_SellableProductPickerSheet> createState() => _SellableProductPickerSheetState();
}

class _SellableProductPickerSheetState extends State<_SellableProductPickerSheet> {
  List<SellableProductModel> _products = [];
  SellableProductModel? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  String? _priceError;

  double get _maxOverridePct {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.maxPriceOverridePct : 10;
  }

  double get _minAllowedPrice => (_selected!.unitPrice * (1 - _maxOverridePct / 100));
  double get _maxAllowedPrice => (_selected!.unitPrice * (1 + _maxOverridePct / 100));

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(
        DelegateSellableProductsFetched(customerId: widget.clientId));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _confirmAdd() {
    final product = _selected;
    if (product == null) return;
    final qty = (double.tryParse(_qtyCtrl.text) ?? 0).clamp(0, product.availableQty).toDouble();
    if (qty <= 0) return;

    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price < _minAllowedPrice || price > _maxAllowedPrice) {
      setState(() => _priceError =
          'السعر يجب أن يكون بين ${_minAllowedPrice.toStringAsFixed(2)} و ${_maxAllowedPrice.toStringAsFixed(2)}');
      return;
    }

    widget.onAdd(InvoiceSaleItem(
      productId: product.productId,
      productName: product.name,
      maxQty: product.availableQty,
      quantity: qty,
      unitPrice: price,
    ));
    Navigator.pop(context);
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
      child: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateSellableProductsLoaded) {
            setState(() => _products = state.products);
          }
        },
        builder: (ctx, state) {
          final loading = state is DelegateLoading && _products.isEmpty;
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('اختر منتجاً من مخزون الشاحنة',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_products.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('لا يوجد مخزون متاح في الشاحنة',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _products[i];
                        final isSelected = _selected?.productId == p.productId;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: AppTheme.primary.withValues(alpha: 0.08),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('متاح: ${p.availableQty.toStringAsFixed(2)} ${p.unit}'),
                          trailing: Text(p.unitPrice.toStringAsFixed(2),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          onTap: () => setState(() {
                            _selected = p;
                            _qtyCtrl.text = '1';
                            _priceCtrl.text = p.unitPrice.toStringAsFixed(2);
                            _priceError = null;
                          }),
                        );
                      },
                    ),
                  ),
                if (_selected != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Text('الكمية (حتى ${_selected!.availableQty.toStringAsFixed(2)})',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            'السعر (بين ${_minAllowedPrice.toStringAsFixed(2)} و ${_maxAllowedPrice.toStringAsFixed(2)})',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          onChanged: (_) {
                            if (_priceError != null) setState(() => _priceError = null);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_priceError != null) ...[
                    const SizedBox(height: 4),
                    Text(_priceError!,
                        style: const TextStyle(fontSize: 11, color: AppTheme.danger)),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _confirmAdd,
                    child: const Text('إضافة'),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Sales-catalog picker (returns) ────────────────────────────────────────────
//
// Sourced from GET /products?is_sales_item=true. The price shown is the
// product's base sale_price for display only — the server always
// re-resolves the authoritative price on submit (never trusts client input).

class _ReturnProductPickerSheet extends StatefulWidget {
  final void Function(InvoiceReturnItem) onAdd;
  const _ReturnProductPickerSheet({required this.onAdd});

  @override
  State<_ReturnProductPickerSheet> createState() => _ReturnProductPickerSheetState();
}

class _ReturnProductPickerSheetState extends State<_ReturnProductPickerSheet> {
  List<CatalogProductModel> _products = [];
  CatalogProductModel? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  String _condition = 'سليم';

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateSalesCatalogFetched());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _confirmAdd() {
    final product = _selected;
    if (product == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    widget.onAdd(InvoiceReturnItem(
      productId: product.id,
      productName: product.name,
      quantity: qty,
      unitPrice: product.salePrice,
      condition: _condition,
    ));
    Navigator.pop(context);
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
      child: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateSalesCatalogLoaded) {
            setState(() => _products = state.products);
          }
        },
        builder: (ctx, state) {
          final loading = state is DelegateLoading && _products.isEmpty;
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('اختر منتجاً للمرتجع',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_products.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('لا توجد منتجات متاحة',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _products[i];
                        final isSelected = _selected?.id == p.id;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: AppTheme.accent.withValues(alpha: 0.08),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p.unit),
                          trailing: Text(p.salePrice.toStringAsFixed(2),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
                          onTap: () => setState(() {
                            _selected = p;
                            _qtyCtrl.text = '1';
                          }),
                        );
                      },
                    ),
                  ),
                if (_selected != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(child: Text('الكمية', style: TextStyle(fontSize: 12))),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('الحالة: '),
                      ChoiceChip(
                        label: const Text('سليم'),
                        selected: _condition == 'سليم',
                        onSelected: (_) => setState(() => _condition = 'سليم'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('تالف'),
                        selected: _condition == 'تالف',
                        onSelected: (_) => setState(() => _condition = 'تالف'),
                        selectedColor: AppTheme.danger.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _confirmAdd,
                    child: const Text('إضافة'),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Read-only price display (server-resolved, never free-typed) ─────────────

class _ReadOnlyPriceField extends StatelessWidget {
  final double price;
  const _ReadOnlyPriceField({required this.price});

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'سعر',
          labelStyle: TextStyle(fontSize: 10),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        child: Text(
          price.toStringAsFixed(2),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      );
}

// ─── Small reusable numeric text field ────────────────────────────────────────

class _SmallNumberField extends StatelessWidget {
  final String label;
  final String initialValue;
  final void Function(String) onChanged;
  const _SmallNumberField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initialValue,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onChanged: onChanged,
      );
}
