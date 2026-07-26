import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/bluetooth_printer.dart';
import '../../../app_config/data/models/app_config_model.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../../delegate/data/models/client_model.dart';
import '../../../delegate/presentation/bloc/delegate_bloc.dart';
import '../../../delegate/presentation/pages/print_invoice_page.dart';
import '../../../delegate/presentation/widgets/add_client_sheet.dart';
import '../../../delegate/presentation/widgets/client_search_field.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// Maps an admin-sale submission result onto the same [InvoicePrintData]
/// shape delegate invoices use, so it can go through the exact same
/// ReceiptPreviewCard/PrintInvoicePage pipeline instead of a parallel one.
/// AdminSaleController has no delegate, so "المندوب:" shows the admin who
/// recorded the sale (r.createdByName) — chosen over omitting the line
/// entirely, since it's genuinely useful here (who processed this sale) and
/// needs no change to the shared buildReceiptPlan().
InvoicePrintData buildAdminSaleReceiptData(AdminSaleResultModel r, {AppConfigModel? config}) {
  final remaining = (r.totalAmount - r.paidAmount).clamp(0, double.infinity).toDouble();
  // customerBalanceAfterSale already includes this sale's own `remaining`
  // (AdminSaleController::store() increments Customer.balance in the same
  // transaction) — subtracting it back out recovers what the customer owed
  // BEFORE this sale, exactly like DelegateInvoiceController's prior_debt
  // snapshot. Safe here because this preview always happens immediately
  // after creation, in the very same response — no time for the balance to
  // have moved for any other reason yet.
  final priorDebt = (r.customerBalanceAfterSale - remaining).clamp(0, double.infinity).toDouble();
  return InvoicePrintData(
    invoiceNumber: r.invoiceNumber ?? '#${r.id}',
    clientName: r.customerName,
    clientPhone: r.customerPhone,
    showPhone: config?.showPhone ?? true,
    delegateName: r.createdByName,
    issuedAt: r.createdAt,
    salesItems: r.items
        .map((i) => PrintLineItem(
              productName: i.productName,
              unit: i.unit,
              quantity: i.quantity,
              unitPrice: i.unitPrice,
              subtotal: i.subtotal,
            ))
        .toList(),
    returnedItems: const [],
    grossSales: r.totalAmount,
    totalReturns: 0,
    netTotal: r.totalAmount,
    cashReceived: r.paidAmount,
    balanceAddedToDebt: remaining,
    priorDebt: priorDebt,
    // AdminSaleController::store() has no overpayment-reduces-prior-debt
    // logic (unlike DelegateInvoiceController) — paidAmount is capped at
    // totalAmount, so no receipt data would ever justify a "تم سداد ..."
    // line for this endpoint.
    debtReduction: 0,
    companyName: config?.companyName ?? '',
    headerText: config?.headerText,
    footerText: config?.footerText,
    logoUrl: config?.logoUrl,
    paperWidthDots: rasterWidthDotsForPaper(config?.paperWidth ?? '80mm'),
  );
}

class _SaleLineItem {
  final int productId;
  final String productName;
  final String unit;
  double quantity;
  double unitPrice;
  _SaleLineItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });
  double get subtotal => quantity * unitPrice;
}

/// "عملية بيع" — an admin/manager-recorded sale not attributed to any
/// delegate, submitted to POST /v1/mobile/admin/sale (see AdminSaleController
/// on the backend). Reuses ClientSearchField from the delegate invoice flow
/// as-is for customer search rather than building a parallel widget; the
/// product picker follows the same server-resolved-price-with-bounded-
/// override pattern invoice_page.dart's _SellableProductPickerSheet uses,
/// just sourced from /admin/products (the general catalog) instead of a
/// delegate's truck stock.
class AdminSalePage extends StatefulWidget {
  const AdminSalePage({super.key});

  @override
  State<AdminSalePage> createState() => _AdminSalePageState();
}

class _AdminSalePageState extends State<AdminSalePage> {
  final _remote = sl<AdminRemoteDataSource>();

  ClientModel? _selectedClient;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<ClientModel> _searchResults = [];
  bool _searchLoading = false;

  List<SimpleProductModel> _products = [];
  List<TreasuryModel> _treasuries = [];
  List<SimpleWarehouseModel> _warehouses = [];
  int? _treasuryId;
  int? _warehouseId;
  bool _loadingRefData = true;

  final List<_SaleLineItem> _items = [];
  final _cashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  double get _maxOverridePct {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.maxPriceOverridePct : 10;
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.subtotal);
  double get _cashReceived => double.tryParse(_cashCtrl.text) ?? 0;
  double get _remainingDebt => (_total - _cashReceived).clamp(0, double.infinity);

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    _loadRefData();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _cashCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus && _searchCtrl.text.isEmpty) {
      _search('');
    }
  }

  Future<void> _loadRefData() async {
    setState(() => _loadingRefData = true);
    try {
      final results = await Future.wait([
        _remote.fetchProducts(),
        _remote.fetchTreasuries(),
        _remote.fetchWarehouses(),
      ]);
      setState(() {
        _products = results[0] as List<SimpleProductModel>;
        _treasuries = results[1] as List<TreasuryModel>;
        _warehouses = results[2] as List<SimpleWarehouseModel>;
        _treasuryId = _treasuries.where((t) => t.isDefault).map((t) => t.id).firstOrNull ??
            (_treasuries.isNotEmpty ? _treasuries.first.id : null);
        _loadingRefData = false;
      });
    } catch (_) {
      setState(() => _loadingRefData = false);
      if (mounted) AppSnackbar.showError(context, 'فشل تحميل بيانات الشاشة.');
    }
  }

  Future<void> _search(String q) async {
    setState(() => _searchLoading = true);
    try {
      final results = await _remote.searchCustomers(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _openAddProductSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProductPickerSheet(
        products: _products,
        maxOverridePct: _maxOverridePct,
        onAdd: (item) => setState(() => _items.add(item)),
      ),
    );
  }

  /// Opens the same AddClientSheet the delegate invoice flow uses — DINV
  /// customer creation (POST /v1/mobile/delegate/clients) now allows
  /// admin/manager callers server-side (the active-DelegateLoading gate on
  /// DelegateClientController::store() only applies when the caller's role
  /// is 'delegate'), and DelegateBloc is provided at the app root for every
  /// role, so this works the same way invoice_page.dart's
  /// _openAddClientSheet does.
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

  Future<void> _submit() async {
    if (_selectedClient == null) {
      AppSnackbar.showError(context, 'يرجى اختيار عميل أولاً.');
      return;
    }
    if (_items.isEmpty) {
      AppSnackbar.showError(context, 'يرجى إضافة صنف واحد على الأقل.');
      return;
    }
    if (_treasuryId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _remote.submitAdminSale(
        customerId: _selectedClient!.id,
        treasuryId: _treasuryId!,
        warehouseId: _warehouseId,
        cashReceived: _cashReceived,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        salesItems: _items
            .map((i) => {
                  'product_id': i.productId,
                  'qty': i.quantity,
                  'unit_price': i.unitPrice,
                })
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _selectedClient = null;
        _searchCtrl.clear();
        _items.clear();
        _cashCtrl.clear();
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(
          context, 'تم حفظ عملية البيع${result.invoiceNumber != null ? ' — ${result.invoiceNumber}' : ''}');

      // Same receipt-preview/print flow delegate invoices use — see
      // buildAdminSaleReceiptData's adapter above. AppConfigBloc.ensureLoaded
      // (not reading .state directly) so a failed startup config fetch
      // doesn't silently print a logo-less receipt (see its doc comment).
      final config = await context.read<AppConfigBloc>().ensureLoaded();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrintInvoicePage(
            initialData: buildAdminSaleReceiptData(result, config: config),
          ),
        ),
      );
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(
          context, e.response?.data?['message'] as String? ?? 'فشل حفظ عملية البيع.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عملية بيع')),
      body: _loadingRefData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ClientSearchField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  results: _searchResults,
                  isLoading: _searchLoading,
                  selectedClient: _selectedClient,
                  onSearch: _search,
                  onSelect: (c) => setState(() {
                    _selectedClient = c;
                    _searchCtrl.text = c.name;
                    _searchResults.clear();
                  }),
                  onAddNew: _openAddClientSheet,
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
                            const Icon(Icons.shopping_cart_outlined,
                                color: AppTheme.primary, size: 18),
                            const SizedBox(width: 4),
                            const Text('الأصناف',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                              onPressed: _openAddProductSheet,
                            ),
                          ],
                        ),
                        if (_items.isEmpty)
                          const Center(
                              child: Text('لا توجد أصناف', style: TextStyle(color: AppTheme.textMuted)))
                        else
                          ..._items.asMap().entries.map((e) => ListTile(
                                dense: true,
                                title: Text(e.value.productName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text(
                                    '${e.value.quantity} ${e.value.unit} × ${e.value.unitPrice.toStringAsFixed(2)} = ${e.value.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 18, color: AppTheme.danger),
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
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _treasuryId,
                  decoration: const InputDecoration(labelText: 'الخزينة'),
                  items:
                      _treasuries.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (v) => setState(() => _treasuryId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'المخزن (اختياري)'),
                  items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cashCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'النقد المستلم', hintText: '0'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                  maxLines: 2,
                ),
                if (_remainingDebt > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('يُضاف للدين:',
                            style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                        Text(_remainingDebt.toStringAsFixed(2),
                            style: const TextStyle(
                                color: AppTheme.danger, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
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
                    label: Text(_submitting ? 'جارٍ الحفظ...' : 'حفظ عملية البيع'),
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

class _ProductPickerSheet extends StatefulWidget {
  final List<SimpleProductModel> products;
  final double maxOverridePct;
  final void Function(_SaleLineItem) onAdd;
  const _ProductPickerSheet(
      {required this.products, required this.maxOverridePct, required this.onAdd});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  SimpleProductModel? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  String? _priceError;

  double get _minAllowed => _selected!.salePrice * (1 - widget.maxOverridePct / 100);
  double get _maxAllowed => _selected!.salePrice * (1 + widget.maxOverridePct / 100);

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _confirmAdd() {
    final product = _selected;
    if (product == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;
    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price < _minAllowed || price > _maxAllowed) {
      setState(() =>
          _priceError = 'السعر يجب أن يكون بين ${_minAllowed.toStringAsFixed(2)} و ${_maxAllowed.toStringAsFixed(2)}');
      return;
    }
    widget.onAdd(_SaleLineItem(
      productId: product.id,
      productName: product.name,
      unit: product.unit,
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
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('اختر منتجاً', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Expanded(
              child: ListView.separated(
                itemCount: widget.products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = widget.products[i];
                  final isSelected = _selected?.id == p.id;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: AppTheme.primary.withValues(alpha: 0.08),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(p.unit),
                    trailing: Text(p.salePrice.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    onTap: () => setState(() {
                      _selected = p;
                      _qtyCtrl.text = '1';
                      _priceCtrl.text = p.salePrice.toStringAsFixed(2);
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
                  const Expanded(child: Text('الكمية', style: TextStyle(fontSize: 12))),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: Text(
                          'السعر (بين ${_minAllowed.toStringAsFixed(2)} و ${_maxAllowed.toStringAsFixed(2)})',
                          style: const TextStyle(fontSize: 12))),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      onChanged: (_) {
                        if (_priceError != null) setState(() => _priceError = null);
                      },
                    ),
                  ),
                ],
              ),
              if (_priceError != null) ...[
                const SizedBox(height: 4),
                Text(_priceError!, style: const TextStyle(fontSize: 11, color: AppTheme.danger)),
              ],
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
