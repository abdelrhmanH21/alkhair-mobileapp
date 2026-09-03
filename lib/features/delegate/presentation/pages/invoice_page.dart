import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/gps_service.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
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
import 'customer_invoice_history_page.dart';

/// Also doubles as the edit form for an already-submitted invoice while its
/// shift is still active (see DelegateInvoiceController::update()) — pass
/// [editingInvoiceId] to fetch and pre-fill that invoice's current items/
/// discount/cash_received instead of starting a blank sale. Reuses every
/// sale-entry widget as-is (product pickers, totals card, validations)
/// rather than a parallel edit form; the only thing edit mode changes is
/// the client field (fixed, not editable — matches the backend, which
/// never lets an edit move an invoice to a different customer) and which
/// bloc event gets dispatched on submit.
class InvoicePage extends StatefulWidget {
  final int? editingInvoiceId;
  const InvoicePage({super.key, this.editingInvoiceId});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

enum _InvoiceReq { search, submit }

class _InvoicePageState extends State<InvoicePage> {
  bool get _isEditing => widget.editingInvoiceId != null;

  // ── Editing: fetch + pre-fill the existing invoice ─────────────────────────
  bool _loadingExisting = false;
  String? _loadExistingError;
  String? _editingInvoiceNumber;
  // Tracks this instance's own outstanding search/submit dispatches by
  // requestId (see request_tracker.dart): InvoicePage can be mounted as both
  // the persistent "البيع" tab AND, simultaneously, a pushed edit-mode
  // instance on top of it (the tab stays alive inside DelegateHomePage's
  // IndexedStack) — both share the same DelegateBloc, so a DelegateFailure
  // meant for one must never be shown by the other.
  final _tracker = RequestTracker<_InvoiceReq>();
  bool _submitting = false;

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
      // Show the last-known full customer list instantly (before the network
      // round trip resolves, or at all if offline — DelegateRepositoryImpl
      // also falls back to this same cache on a failed search) instead of a
      // spinner sitting over a still-empty dropdown.
      final delegateBloc = context.read<DelegateBloc>();
      final cached = delegateBloc.getCachedCustomerList();
      final event = DelegateClientSearchRequested('');
      _tracker.start(event.requestId, _InvoiceReq.search);
      setState(() {
        if (cached.isNotEmpty) _searchResults = cached;
        _searchLoading = cached.isEmpty;
      });
      delegateBloc.add(event);
    }
  }

  // ── Sales line items ───────────────────────────────────────────────────────
  final List<InvoiceSaleItem> _salesItems = [];

  // ── Return line items ──────────────────────────────────────────────────────
  final List<InvoiceReturnItem> _returnItems = [];

  // ── Cash received ──────────────────────────────────────────────────────────
  final _cashCtrl = TextEditingController();

  // ── Discount (empty by default — never prefilled with 0) ──────────────────
  final _discountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChanged);
    if (_isEditing) {
      _loadExistingInvoice();
    }
  }

  /// Fetches the invoice-to-edit directly (like invoice_detail_page.dart/
  /// print_invoice_page.dart do) rather than through DelegateBloc — this
  /// page can be pushed on top of another bloc-listening screen (the
  /// InvoiceHistoryPage/InvoiceDetailPage it was opened from), and a
  /// DelegateLoading()/DelegateFailure() emitted here for a plain data load
  /// would leak into that screen's own listener.
  Future<void> _loadExistingInvoice() async {
    setState(() {
      _loadingExisting = true;
      _loadExistingError = null;
    });
    try {
      final api = sl<ApiClient>();
      final res = await api.dio
          .get('${ApiEndpoints.delegateInvoices}/${widget.editingInvoiceId}');
      final invoice = res.data['data'] as Map<String, dynamic>;
      final customer = invoice['customer'] as Map<String, dynamic>? ?? {};
      final items =
          (invoice['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final returns =
          (invoice['returns'] as List? ?? []).cast<Map<String, dynamic>>();

      final client = ClientModel(
        id: customer['id'] as int,
        name: customer['name'] as String? ?? '',
        phone: customer['phone'] as String? ?? '',
        address: customer['address'] as String?,
        balance: (customer['balance'] as num? ?? 0).toDouble(),
      );

      final discount = (invoice['discount_amount'] as num? ?? 0).toDouble();
      final cash = (invoice['cash_received'] as num? ?? 0).toDouble();

      setState(() {
        _editingInvoiceNumber = invoice['invoice_number'] as String?;
        _selectedClient = client;
        _searchCtrl.text = client.name;
        _salesItems
          ..clear()
          ..addAll(items.map((m) {
            final p = m['product'] as Map<String, dynamic>? ?? {};
            return InvoiceSaleItem(
              productId: m['product_id'] as int,
              productName: p['name'] as String? ?? '',
              // No client-side cap for the invoice's own pre-filled items:
              // the true max (current truck stock + this item's own already-
              // deducted quantity, once the server reverses it) isn't known
              // client-side without an extra stock fetch — the server still
              // authoritatively enforces it via DelegateTruckStock::deductStock
              // when the edit is submitted.
              quantity: (m['quantity'] as num).toDouble(),
              unitPrice: (m['unit_price'] as num).toDouble(),
            );
          }));
        _returnItems
          ..clear()
          ..addAll(returns.map((m) {
            final p = m['product'] as Map<String, dynamic>? ?? {};
            return InvoiceReturnItem(
              productId: m['product_id'] as int,
              productName: p['name'] as String? ?? '',
              quantity: (m['quantity'] as num).toDouble(),
              unitPrice: (m['unit_price'] as num).toDouble(),
              condition: m['condition'] as String? ?? 'سليم',
            );
          }));
        _discountCtrl.text = discount > 0 ? discount.toStringAsFixed(2) : '';
        _cashCtrl.text = cash.toStringAsFixed(2);
        _loadingExisting = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loadingExisting = false;
        _loadExistingError = e.response?.data?['message'] as String? ??
            'فشل تحميل بيانات الفاتورة للتعديل.';
      });
    } catch (_) {
      setState(() {
        _loadingExisting = false;
        _loadExistingError = 'حدث خطأ غير متوقع أثناء تحميل الفاتورة.';
      });
    }
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _cashCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  double get _grossSales => _salesItems.fold(0.0, (s, i) => s + i.subtotal);

  double get _totalReturns => _returnItems.fold(0.0, (s, i) => s + i.subtotal);

  // Only in-kind-replacement returns contribute — see computeInvoiceNetTotal's
  // doc comment for why this is added back on top rather than folded into
  // _totalReturns' existing meaning.
  double get _replacementItemsTotal => _returnItems
      .where((r) => r.refundMethod == 'in_kind_replacement')
      .fold(0.0, (s, r) => s + (r.replacementSubtotal ?? 0));

  double get _discountAmount => double.tryParse(_discountCtrl.text) ?? 0;

  double get _maxDiscountPct {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.maxPriceDiscountPct : 20;
  }

  double get _maxDiscount => _grossSales * (_maxDiscountPct / 100);

  String? get _discountError => _discountAmount > _maxDiscount
      ? 'الخصم يتجاوز الحد المسموح (${_maxDiscountPct.toStringAsFixed(0)}% = ${_maxDiscount.toStringAsFixed(2)})'
      : null;

  double get _netTotal => computeInvoiceNetTotal(
        grossSales: _grossSales,
        discountAmount: _discountAmount,
        totalReturns: _totalReturns,
        replacementItemsTotal: _replacementItemsTotal,
      );

  double get _cashReceived => double.tryParse(_cashCtrl.text) ?? 0;

  double get _remainingDebt =>
      (_netTotal - _cashReceived).clamp(0, double.infinity);

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
    if (_discountError != null) {
      _showError(_discountError!);
      return;
    }

    // Editing an existing invoice always needs a live round trip (it
    // reverses/re-derives server-side state — see DelegateInvoiceController
    // ::update()'s doc comment) — only a brand-new sale can be queued
    // offline. If offline, skip the bloc/network entirely and save locally.
    if (!_isEditing && !sl<ConnectivityService>().isOnline) {
      _queueOfflineSale();
      return;
    }

    final DelegateEvent event = _isEditing
        ? DelegateInvoiceUpdateRequested(
            invoiceId: widget.editingInvoiceId!,
            salesItems: _salesItems,
            returnedItems: _returnItems,
            cashReceived: _cashReceived,
            discountAmount: _discountAmount,
          )
        : DelegateInvoiceSubmitted(
            clientId: _selectedClient!.id,
            salesItems: _salesItems,
            returnedItems: _returnItems,
            cashReceived: _cashReceived,
            discountAmount: _discountAmount,
          );
    _tracker.start(event.requestId, _InvoiceReq.submit);
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(event);
  }

  /// Phase 2 offline support: instead of attempting (and failing) a network
  /// call, queue this sale locally with a client-generated idempotency key,
  /// apply an optimistic truck-stock deduction (so a second offline sale for
  /// the same product doesn't see stale, too-high availability), and confirm
  /// with a visually distinct "saved locally" message — never the same
  /// green success styling as a real confirmed submission, since the
  /// delegate needs to know this hasn't actually reached the server yet.
  Future<void> _queueOfflineSale() async {
    setState(() => _submitting = true);

    final coords = await sl<GpsService>().captureCoordinates();
    final client = _selectedClient!;
    final payload = <String, dynamic>{
      'client_id': client.id,
      'client_name': client.name,
      'sales_items': _salesItems
          .map((s) => {
                'product_id': s.productId,
                'product_name': s.productName,
                'qty': s.quantity,
                'unit_price': s.unitPrice,
              })
          .toList(),
      'returned_items': _returnItems
          .map((r) => {
                'product_id': r.productId,
                'product_name': r.productName,
                'qty': r.quantity,
                'unit_price': r.unitPrice,
                'condition': r.condition,
                'refund_method': r.refundMethod,
                if (r.replacementProductId != null)
                  'replacement_product_id': r.replacementProductId,
                if (r.replacementProductName != null)
                  'replacement_product_name': r.replacementProductName,
                if (r.replacementQuantity != null)
                  'replacement_quantity': r.replacementQuantity,
                if (r.replacementUnitPrice != null)
                  'replacement_unit_price': r.replacementUnitPrice,
              })
          .toList(),
      'cash_received': _cashReceived,
      'discount_amount': _discountAmount,
      'latitude': coords.lat,
      'longitude': coords.lng,
    };

    await sl<PendingActionQueue>().enqueue(PendingAction(
      idempotencyKey: generateIdempotencyKey(),
      type: PendingActionType.sale,
      payload: payload,
      createdAt: DateTime.now(),
    ));

    // Sold items reduce available stock; 'سليم' returns add back to it; an
    // in-kind-replacement return's replacement product reduces stock the
    // same way a sale does — same net-effect DelegateTruckStock::deductStock/
    // addStock would apply server-side, applied locally so it's reflected
    // immediately.
    final delta = <int, double>{};
    for (final s in _salesItems) {
      delta[s.productId] = (delta[s.productId] ?? 0) - s.quantity;
    }
    for (final r in _returnItems) {
      if (r.condition == 'سليم') {
        delta[r.productId] = (delta[r.productId] ?? 0) + r.quantity;
      }
      if (r.refundMethod == 'in_kind_replacement' && r.replacementProductId != null) {
        delta[r.replacementProductId!] =
            (delta[r.replacementProductId!] ?? 0) - (r.replacementQuantity ?? 0);
      }
    }
    if (mounted) {
      await context.read<DelegateBloc>().applyOptimisticTruckStockDelta(delta);
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _selectedClient = null;
      _salesItems.clear();
      _returnItems.clear();
      _cashCtrl.clear();
      _discountCtrl.clear();
      _searchCtrl.clear();
      _searchResults.clear();
    });
    AppSnackbar.showQueued(
      context,
      'تم الحفظ محليًا، سيتم الإرسال عند توفر الإنترنت.',
    );
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
        title: Text(_isEditing
            ? 'تعديل الفاتورة${_editingInvoiceNumber != null ? ' ${_editingInvoiceNumber!}' : ''}'
            : 'فاتورة جديدة'),
        actions: _isEditing
            ? const []
            : [
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'سجل الفواتير',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                                value: context.read<DelegateBloc>(),
                                child: const InvoiceHistoryPage(hasActiveLoading: true),
                              ))),
                ),
                IconButton(
                  icon: const Icon(Icons.inventory_rounded),
                  tooltip: 'مخزون الشاحنة',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                                value: context.read<DelegateBloc>(),
                                child: const TruckStockPage(),
                              ))),
                ),
                IconButton(
                  icon: const Icon(Icons.dashboard_outlined),
                  tooltip: 'لوحة الأداء',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                                value: context.read<DelegateBloc>(),
                                child: const DashboardPage(),
                              ))),
                ),
              ],
      ),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : _loadExistingError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppTheme.danger),
                        const SizedBox(height: 12),
                        Text(_loadExistingError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadExistingInvoice,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    return BlocListener<DelegateBloc, DelegateState>(
      listener: (ctx, state) {
        if (state is DelegateClientSearchResults) {
          if (_tracker.resolve(state.requestId) == null) return;
          setState(() {
            _searchResults = state.clients;
            _searchLoading = false;
          });
        }
        if (state is DelegateInvoiceSubmittedState) {
          if (_tracker.resolve(state.requestId) == null) return;
          final invoice = state.invoice;
          _submitting = false;
          // Reset form
          setState(() {
            _selectedClient = null;
            _salesItems.clear();
            _returnItems.clear();
            _cashCtrl.clear();
            _discountCtrl.clear();
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
        if (state is DelegateInvoiceUpdatedState) {
          if (_tracker.resolve(state.requestId) == null) return;
          _submitting = false;
          AppSnackbar.showSuccess(ctx, 'تم تعديل الفاتورة بنجاح');
          // Signal success to whoever pushed this edit form (invoice
          // history/detail page) so it can refresh its own data.
          Navigator.pop(ctx, true);
        }
        if (state is DelegateFailure) {
          final kind = _tracker.resolve(state.requestId);
          if (kind == null) {
            // Not ours — e.g. a concurrent request from the persistent
            // "البيع" tab still mounted below this pushed edit-mode instance.
            return;
          }
          setState(() {
            if (kind == _InvoiceReq.submit) _submitting = false;
            if (kind == _InvoiceReq.search) _searchLoading = false;
          });
          _showError(state.message);
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Customer is fixed once an invoice exists — the backend never
            // lets an edit move an invoice to a different customer — so
            // edit mode shows a plain read-only card instead of the
            // interactive search field.
            if (_isEditing)
              _EditingClientCard(client: _selectedClient)
            else
              ClientSearchField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                results: _searchResults,
                isLoading: _searchLoading,
                selectedClient: _selectedClient,
                onSearch: (q) {
                  final event = DelegateClientSearchRequested(q);
                  _tracker.start(event.requestId, _InvoiceReq.search);
                  setState(() => _searchLoading = true);
                  context.read<DelegateBloc>().add(event);
                },
                onSelect: (c) => setState(() {
                  _selectedClient = c;
                  _searchCtrl.text = c.name;
                  _searchResults.clear();
                }),
                onAddNew: _openAddClientSheet,
                onViewHistory: (c) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerInvoiceHistoryPage(
                      customerId: c.id,
                      customerName: c.name,
                    ),
                  ),
                ),
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
                    clientId: _selectedClient?.id,
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
              replacementItemsTotal: _replacementItemsTotal,
              discountCtrl: _discountCtrl,
              discountError: _discountError,
              netTotal: _netTotal,
              cashCtrl: _cashCtrl,
              remainingDebt: _remainingDebt,
              onCashChanged: () => setState(() {}),
              onDiscountChanged: () => setState(() {}),
            ),
            const SizedBox(height: 16),

            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submitInvoice,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(_submitting
                    ? 'جارٍ الحفظ...'
                    : (_isEditing ? 'حفظ التعديلات' : 'إصدار الفاتورة')),
                style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 17)),
              ),
            ),
            // Keyed purely so widget tests can target guaranteed-blank form
            // space (below the submit button) for the tap-to-dismiss-
            // keyboard gesture without guessing screen coordinates.
            const SizedBox(height: 24, key: Key('invoiceFormBottomSpacer')),
          ],
        ),
      ),
    );
  }
}

// ─── Edit-mode client display (read-only — customer can't be changed) ─────────

class _EditingClientCard extends StatelessWidget {
  final ClientModel? client;
  const _EditingClientCard({required this.client});

  @override
  Widget build(BuildContext context) {
    final c = client;
    if (c == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(c.phone,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sales Section ─────────────────────────────────────────────────────────────

class _SalesSection extends StatelessWidget {
  final List<InvoiceSaleItem> items;
  final int? clientId;
  final VoidCallback onChange;
  const _SalesSection(
      {required this.items, required this.clientId, required this.onChange});

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
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)))
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
                    label: item.maxQty.isFinite
                        ? 'كمية (حتى ${item.maxQty.toStringAsFixed(0)})'
                        : 'كمية',
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
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
}

// ─── Returns Section ───────────────────────────────────────────────────────────

class _ReturnsSection extends StatelessWidget {
  final List<InvoiceReturnItem> items;
  // Threaded through to the replacement-product picker (reuses the exact
  // same _SellableProductPickerSheet the sales side uses) so an in-kind
  // replacement's price resolves against the same customer's price level
  // as everything else on this invoice.
  final int? clientId;
  final VoidCallback onChange;
  const _ReturnsSection(
      {required this.items, required this.clientId, required this.onChange});

  void _addItem(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _ReturnProductPickerSheet(
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
                  const Icon(Icons.assignment_return_outlined,
                      color: AppTheme.accent, size: 18),
                  const SizedBox(width: 4),
                  const Text('المرتجعات',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)))
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
            // Refund method — set once when this return was added (see
            // _ReturnProductPickerSheet); shown read-only here since editing
            // it after the fact would also require re-picking the
            // replacement product.
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                widget.item.refundMethod == 'in_kind_replacement'
                    ? 'بدل عيني: ${widget.item.replacementProductName ?? ''} '
                        '×${(widget.item.replacementQuantity ?? 0).toStringAsFixed(2)} '
                        '= ${(widget.item.replacementSubtotal ?? 0).toStringAsFixed(2)}'
                    : 'الاسترجاع: كاش',
                style: const TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
      );
}

// ─── Totals Card ───────────────────────────────────────────────────────────────

class _TotalsCard extends StatelessWidget {
  final double grossSales;
  final double totalReturns;
  // Sum of in-kind-replacement returns' replacement-product value — see
  // computeInvoiceNetTotal's doc comment. 0 when every return (if any) is
  // a plain cash refund, matching today's behavior exactly.
  final double replacementItemsTotal;
  final TextEditingController discountCtrl;
  final String? discountError;
  final double netTotal;
  final TextEditingController cashCtrl;
  final double remainingDebt;
  final VoidCallback onCashChanged;
  final VoidCallback onDiscountChanged;

  const _TotalsCard({
    required this.grossSales,
    required this.totalReturns,
    required this.replacementItemsTotal,
    required this.discountCtrl,
    required this.discountError,
    required this.netTotal,
    required this.cashCtrl,
    required this.remainingDebt,
    required this.onCashChanged,
    required this.onDiscountChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _TotalRow('إجمالي المبيعات', grossSales, AppTheme.primary),
              _TotalRow('إجمالي المرتجعات', -totalReturns, AppTheme.accent),
              if (replacementItemsTotal > 0)
                _TotalRow('بدل عيني (إضافة)', replacementItemsTotal, AppTheme.primary),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('الخصم:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      key: const Key('invoiceDiscountField'),
                      controller: discountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '0',
                        errorText: discountError,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => onDiscountChanged(),
                    ),
                  ),
                ],
              ),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
  const _SellableProductPickerSheet(
      {required this.clientId, required this.onAdd});

  @override
  State<_SellableProductPickerSheet> createState() =>
      _SellableProductPickerSheetState();
}

class _SellableProductPickerSheetState
    extends State<_SellableProductPickerSheet> {
  List<SellableProductModel> _products = [];
  SellableProductModel? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  String? _priceError;

  // This sheet shares the same DelegateBloc as the InvoicePage underneath
  // it (and, if reopened quickly, a previous instance of itself mid pop-
  // animation) — track our own fetch by requestId so its result can't be
  // confused with either. See request_tracker.dart.
  final _tracker = RequestTracker<bool>();

  // True while `_products` came from OfflineCacheService rather than a
  // confirmed-fresh network response — drives the calm offline banner (see
  // OfflineDataBanner), never a red error, since a stale-but-real truck-stock
  // list is exactly what Phase 1 offline support is meant to keep showing.
  bool _isCachedFallback = false;

  double get _maxDiscountPct {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.maxPriceDiscountPct : 20;
  }

  // Discount is capped below the resolved price; a markup above it has no
  // upper bound — mirrors DelegateInvoiceController::resolveBoundedPrice().
  double get _minAllowedPrice =>
      (_selected!.unitPrice * (1 - _maxDiscountPct / 100));

  @override
  void initState() {
    super.initState();
    final cached = context.read<DelegateBloc>().getCachedSellableProducts();
    if (cached.isNotEmpty) {
      _products = cached;
      _isCachedFallback = true;
    }
    final event = DelegateSellableProductsFetched(customerId: widget.clientId);
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
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
    final qty = (double.tryParse(_qtyCtrl.text) ?? 0)
        .clamp(0, product.availableQty)
        .toDouble();
    if (qty <= 0) return;

    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price < _minAllowedPrice) {
      setState(() => _priceError =
          'الحد الأدنى: ${_minAllowedPrice.toStringAsFixed(2)} (خصم حتى ${_maxDiscountPct.toStringAsFixed(0)}%) — لا يوجد حد أقصى للزيادة');
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
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() {
              _products = state.products;
              _isCachedFallback = false;
            });
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            // A cached list (if any) is already showing — nothing to do
            // beyond letting the calm offline banner reflect that below;
            // never surface a red error here for what's just a background
            // refresh failing behind still-valid last-known data.
            setState(() {});
          }
        },
        builder: (ctx, state) {
          final loading = _tracker.hasPending(true) && _products.isEmpty;
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('اختر منتجاً من مخزون الشاحنة',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                OfflineDataBanner(show: _isCachedFallback),
                if (loading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (_products.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('لا يوجد مخزون متاح في الشاحنة',
                          style: TextStyle(color: AppTheme.textMuted)),
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
                          selectedTileColor:
                              AppTheme.primary.withValues(alpha: 0.08),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              'متاح: ${p.availableQty.toStringAsFixed(2)} ${p.unit}'),
                          trailing: Text(p.unitPrice.toStringAsFixed(2),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary)),
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
                        child: Text(
                            'الكمية (حتى ${_selected!.availableQty.toStringAsFixed(2)})',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                            'السعر (الحد الأدنى: ${_minAllowedPrice.toStringAsFixed(2)} — لا يوجد حد أقصى)',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          onChanged: (_) {
                            if (_priceError != null) {
                              setState(() => _priceError = null);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_priceError != null) ...[
                    const SizedBox(height: 4),
                    Text(_priceError!,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.danger)),
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
  // Needed to open the replacement-product picker (_SellableProductPickerSheet)
  // with the correct customer price level when "بدل عيني" is chosen.
  final int? clientId;
  final void Function(InvoiceReturnItem) onAdd;
  const _ReturnProductPickerSheet({required this.clientId, required this.onAdd});

  @override
  State<_ReturnProductPickerSheet> createState() =>
      _ReturnProductPickerSheetState();
}

class _ReturnProductPickerSheetState extends State<_ReturnProductPickerSheet> {
  List<CatalogProductModel> _products = [];
  CatalogProductModel? _selected;
  final _qtyCtrl = TextEditingController(text: '1');
  String _condition = 'سليم';

  // ── Refund method ("طريقة الاسترجاع") ───────────────────────────────────
  String _refundMethod = 'cash';
  int? _replacementProductId;
  String? _replacementProductName;
  double? _replacementQuantity;
  double? _replacementUnitPrice;
  String? _refundError;

  // See _SellableProductPickerSheetState's identical comment.
  final _tracker = RequestTracker<bool>();

  @override
  void initState() {
    super.initState();
    final event = DelegateSalesCatalogFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _resetReplacement() {
    _replacementProductId = null;
    _replacementProductName = null;
    _replacementQuantity = null;
    _replacementUnitPrice = null;
  }

  /// Opens the SAME truck-stock picker the sales side uses
  /// (_SellableProductPickerSheet) so a "بدل عيني" replacement is priced
  /// and stock-capped identically to any other item handed off this truck.
  Future<void> _pickReplacement() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => BlocProvider.value(
        value: context.read<DelegateBloc>(),
        child: _SellableProductPickerSheet(
          clientId: widget.clientId,
          onAdd: (item) => setState(() {
            _replacementProductId = item.productId;
            _replacementProductName = item.productName;
            _replacementQuantity = item.quantity;
            _replacementUnitPrice = item.unitPrice;
            _refundError = null;
          }),
        ),
      ),
    );
  }

  void _confirmAdd() {
    final product = _selected;
    if (product == null) return;
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) return;

    if (_refundMethod == 'in_kind_replacement' && _replacementProductId == null) {
      setState(() => _refundError = 'يجب اختيار منتج البديل والكمية.');
      return;
    }

    widget.onAdd(InvoiceReturnItem(
      productId: product.id,
      productName: product.name,
      quantity: qty,
      unitPrice: product.salePrice,
      condition: _condition,
      refundMethod: _refundMethod,
      replacementProductId: _replacementProductId,
      replacementProductName: _replacementProductName,
      replacementQuantity: _replacementQuantity,
      replacementUnitPrice: _replacementUnitPrice,
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
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _products = state.products);
          }
        },
        builder: (ctx, state) {
          final loading = _tracker.hasPending(true) && _products.isEmpty;
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('اختر منتجاً للمرتجع',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (loading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (_products.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('لا توجد منتجات متاحة',
                          style: TextStyle(color: AppTheme.textMuted)),
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
                          selectedTileColor:
                              AppTheme.accent.withValues(alpha: 0.08),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p.unit),
                          trailing: Text(p.salePrice.toStringAsFixed(2),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent)),
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
                      const Expanded(
                          child:
                              Text('الكمية', style: TextStyle(fontSize: 12))),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
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
                  Row(
                    children: [
                      const Text('طريقة الاسترجاع: '),
                      ChoiceChip(
                        label: const Text('كاش'),
                        selected: _refundMethod == 'cash',
                        onSelected: (_) => setState(() {
                          _refundMethod = 'cash';
                          _resetReplacement();
                          _refundError = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('بدل عيني'),
                        selected: _refundMethod == 'in_kind_replacement',
                        selectedColor: AppTheme.primary.withValues(alpha: 0.3),
                        onSelected: (_) {
                          setState(() {
                            _refundMethod = 'in_kind_replacement';
                            _refundError = null;
                          });
                          _pickReplacement();
                        },
                      ),
                    ],
                  ),
                  if (_refundMethod == 'in_kind_replacement') ...[
                    const SizedBox(height: 6),
                    if (_replacementProductId == null)
                      OutlinedButton.icon(
                        onPressed: _pickReplacement,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('اختر منتج البديل'),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'بدل: $_replacementProductName '
                                '×${_replacementQuantity!.toStringAsFixed(2)} '
                                '= ${(_replacementQuantity! * _replacementUnitPrice!).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: _pickReplacement,
                              child: const Text('تغيير',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    if (_refundError != null) ...[
                      const SizedBox(height: 4),
                      Text(_refundError!,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.danger)),
                    ],
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
