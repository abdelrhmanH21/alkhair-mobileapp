import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/report_export.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../app_config/presentation/bloc/app_config_bloc.dart';
import '../../../app_config/presentation/bloc/app_config_state.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

final _fmt = DateFormat('yyyy-MM-dd');

const Map<String, String> _typeLabels = {
  'goods_issued': 'تسليم بضاعة',
  'goods_returned': 'استرجاع بضاعة',
  'payment': 'دفعة',
};

/// كشف حساب موزع + الإجراءات الثلاثة المستقلة (تسليم/استرجاع بضاعة، تسجيل
/// دفعة) + تعديل حركة سابقة. Mirrors AdminDistributorController's endpoints
/// directly (called via AdminRemoteDataSource), same "page pushed from a
/// list" convention every other admin operation page in this app follows —
/// no shared bloc involvement.
class DistributorDetailPage extends StatefulWidget {
  final int distributorId;
  final String distributorName;
  const DistributorDetailPage({super.key, required this.distributorId, required this.distributorName});

  @override
  State<DistributorDetailPage> createState() => _DistributorDetailPageState();
}

class _DistributorDetailPageState extends State<DistributorDetailPage> {
  final _remote = sl<AdminRemoteDataSource>();

  DistributorStatementModel? _statement;
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  List<SimpleProductModel> _products = [];
  List<TreasuryModel> _treasuries = [];
  bool _refDataLoaded = false;

  bool _printingDay = false;
  bool _printingFull = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRefData();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statement = await _remote.fetchDistributorStatement(widget.distributorId);
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'فشل تحميل كشف الحساب.';
      });
    }
  }

  Future<void> _loadRefData() async {
    try {
      final results = await Future.wait([_remote.fetchProducts(), _remote.fetchTreasuries()]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<SimpleProductModel>;
        _treasuries = results[1] as List<TreasuryModel>;
        _refDataLoaded = true;
      });
    } catch (_) {
      // Non-fatal at page load — the action sheets re-check and show a
      // clear error if a product/treasury picker is opened before this
      // resolves or if it never does.
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _openGoodsSheet({required String type, DistributorTransactionModel? editing}) {
    if (!_refDataLoaded) {
      AppSnackbar.showError(context, 'جاري تحميل بيانات المنتجات، حاول بعد قليل.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _GoodsFormSheet(
        type: type,
        editing: editing,
        products: _products,
        defaultDate: _selectedDate,
        onSubmit: (transactionDate, items, notes) async {
          try {
            if (editing != null) {
              await _remote.updateDistributorTransaction(
                distributorId: widget.distributorId,
                transactionId: editing.id,
                body: {'transaction_date': transactionDate, 'items': items, if (notes != null) 'notes': notes},
              );
            } else if (type == 'goods_issued') {
              await _remote.issueDistributorGoods(
                  distributorId: widget.distributorId, transactionDate: transactionDate, items: items, notes: notes);
            } else {
              await _remote.returnDistributorGoods(
                  distributorId: widget.distributorId, transactionDate: transactionDate, items: items, notes: notes);
            }
            if (!mounted) return;
            Navigator.pop(context);
            AppSnackbar.showSuccess(context, 'تم الحفظ بنجاح.');
            _load();
          } on DioException catch (e) {
            AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل الحفظ.');
          } catch (_) {
            AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
          }
        },
      ),
    );
  }

  void _openPaymentSheet({DistributorTransactionModel? editing}) {
    if (!_refDataLoaded) {
      AppSnackbar.showError(context, 'جاري تحميل بيانات الخزائن، حاول بعد قليل.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PaymentFormSheet(
        editing: editing,
        treasuries: _treasuries,
        defaultDate: _selectedDate,
        onSubmit: (transactionDate, amount, treasuryId, notes) async {
          try {
            if (editing != null) {
              await _remote.updateDistributorTransaction(
                distributorId: widget.distributorId,
                transactionId: editing.id,
                body: {
                  'transaction_date': transactionDate,
                  'amount': amount,
                  'treasury_id': treasuryId,
                  if (notes != null) 'notes': notes,
                },
              );
            } else {
              await _remote.payDistributor(
                distributorId: widget.distributorId,
                transactionDate: transactionDate,
                amount: amount,
                treasuryId: treasuryId,
                notes: notes,
              );
            }
            if (!mounted) return;
            Navigator.pop(context);
            AppSnackbar.showSuccess(context, 'تم تسجيل الدفعة بنجاح.');
            _load();
          } on DioException catch (e) {
            AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل الحفظ.');
          } catch (_) {
            AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
          }
        },
      ),
    );
  }

  void _openRowForEdit(DistributorTransactionModel tx) {
    if (tx.type == 'payment') {
      _openPaymentSheet(editing: tx);
    } else {
      _openGoodsSheet(type: tx.type, editing: tx);
    }
  }

  String get _companyName {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? state.config.companyName : '';
  }

  String? get _logoUrl {
    final state = context.read<AppConfigBloc>().state;
    return state is AppConfigLoaded ? (state.config.logoColorUrl ?? state.config.logoUrl) : null;
  }

  ReportExportData _buildExportData(String title, String period, List<DistributorTransactionModel> rows, double balanceEnd) {
    return ReportExportData(
      title: title,
      period: period,
      headers: const ['التاريخ', 'النوع', 'التفاصيل', 'القيمة', 'الرصيد بعدها'],
      rows: rows
          .map((tx) => [
                tx.transactionDate,
                _typeLabels[tx.type] ?? tx.type,
                tx.isGoods
                    ? tx.items.map((i) => '${i.productName} ×${i.quantity.toStringAsFixed(2)}').join('، ')
                    : 'خزينة: ${tx.treasuryName ?? '-'}',
                '${tx.type == 'goods_issued' ? '+' : '-'}${tx.amount.toStringAsFixed(2)}',
                tx.balanceAfter.toStringAsFixed(2),
              ])
          .toList(),
      totals: ['الرصيد', '-', '-', '-', balanceEnd.toStringAsFixed(2)],
    );
  }

  Future<void> _printDayReceipt() async {
    setState(() => _printingDay = true);
    try {
      final receipt = await _remote.fetchDistributorDailyReceipt(
        distributorId: widget.distributorId,
        date: _fmt.format(_selectedDate),
      );
      await ReportExporter.exportPdf(
        _buildExportData('فاتورة يومية — ${widget.distributorName}', _fmt.format(_selectedDate), receipt.transactions, receipt.balanceAfter),
        companyName: _companyName,
        logoUrl: _logoUrl,
      );
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء الفاتورة. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _printingDay = false);
    }
  }

  Future<void> _printFullStatement() async {
    final statement = _statement;
    if (statement == null || statement.transactions.isEmpty) {
      AppSnackbar.showError(context, 'لا توجد حركات لطباعتها.');
      return;
    }
    setState(() => _printingFull = true);
    try {
      await ReportExporter.exportPdf(
        _buildExportData('كشف حساب تفصيلي — ${widget.distributorName}', 'حتى ${_fmt.format(DateTime.now())}',
            statement.transactions, statement.distributor.runningBalance),
        companyName: _companyName,
        logoUrl: _logoUrl,
      );
    } catch (_) {
      if (mounted) AppSnackbar.showError(context, 'تعذر إنشاء الكشف. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _printingFull = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.distributorName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _load)
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final statement = _statement!;
    final balance = statement.distributor.runningBalance;
    final owesUs = balance > 0;
    final settled = balance == 0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (settled ? AppTheme.textMuted : owesUs ? AppTheme.danger : AppTheme.secondary).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الرصيد المستحق', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${balance.abs().toStringAsFixed(2)}${settled ? ' (مسوّى)' : owesUs ? ' (مستحق)' : ' (رصيد له)'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: settled ? AppTheme.textMuted : owesUs ? AppTheme.danger : AppTheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text('تاريخ العملية: ${_fmt.format(_selectedDate)}'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openGoodsSheet(type: 'goods_issued'),
                icon: const Icon(Icons.remove_shopping_cart_outlined, size: 16),
                label: const Text('تسليم بضاعة'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
                onPressed: () => _openGoodsSheet(type: 'goods_returned'),
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 16),
                label: const Text('استرجاع بضاعة'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                onPressed: () => _openPaymentSheet(),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('تسجيل دفعة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printingDay ? null : _printDayReceipt,
                  icon: _printingDay
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('طباعة فاتورة اليوم'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printingFull ? null : _printFullStatement,
                  icon: _printingFull
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.summarize_outlined, size: 16),
                  label: const Text('كشف حساب تفصيلي'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('كشف الحساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (statement.transactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('لا توجد حركات بعد.', style: TextStyle(color: AppTheme.textMuted))),
            )
          else
            ...statement.transactions.reversed.map((tx) => _TransactionCard(tx: tx, onTap: () => _openRowForEdit(tx))),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final DistributorTransactionModel tx;
  final VoidCallback onTap;
  const _TransactionCard({required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isIssue = tx.type == 'goods_issued';
    final color = isIssue ? AppTheme.danger : AppTheme.secondary;
    final detail = tx.isGoods
        ? tx.items.map((i) => '${i.productName} ×${i.quantity.toStringAsFixed(2)}').join('، ')
        : 'خزينة: ${tx.treasuryName ?? '-'}';

    return Card(
      color: AppTheme.cardBg,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(_typeLabels[tx.type] ?? tx.type,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Text(tx.transactionDate, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ]),
                  const Icon(Icons.edit_outlined, size: 15, color: AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(fontSize: 12)),
              if (tx.notes != null && tx.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tx.notes!, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${isIssue ? '+' : '-'}${tx.amount.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                  Text('الرصيد بعدها: ${tx.balanceAfter.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── تسليم/استرجاع بضاعة — create or edit ─────────────────────────────────

class _DraftItem {
  final int productId;
  final String productName;
  final String unit;
  final double quantity;
  final double unitPrice;
  const _DraftItem({required this.productId, required this.productName, required this.unit, required this.quantity, required this.unitPrice});
  double get subtotal => quantity * unitPrice;
}

class _GoodsFormSheet extends StatefulWidget {
  final String type; // 'goods_issued' | 'goods_returned'
  final DistributorTransactionModel? editing;
  final List<SimpleProductModel> products;
  final DateTime defaultDate;
  final void Function(String transactionDate, List<Map<String, dynamic>> items, String? notes) onSubmit;
  const _GoodsFormSheet({
    required this.type,
    required this.editing,
    required this.products,
    required this.defaultDate,
    required this.onSubmit,
  });

  @override
  State<_GoodsFormSheet> createState() => _GoodsFormSheetState();
}

class _GoodsFormSheetState extends State<_GoodsFormSheet> {
  late DateTime _date;
  late List<_DraftItem> _items;
  final _notesCtrl = TextEditingController();
  SimpleProductModel? _selectedProduct;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _date = widget.editing != null ? DateTime.parse(widget.editing!.transactionDate) : widget.defaultDate;
    _items = widget.editing?.items
            .map((i) => _DraftItem(productId: i.productId, productName: i.productName, unit: i.unit, quantity: i.quantity, unitPrice: i.unitPrice))
            .toList() ??
        [];
    _notesCtrl.text = widget.editing?.notes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _date = picked);
  }

  void _addItem() {
    final product = _selectedProduct;
    final qty = double.tryParse(_qtyCtrl.text);
    final price = double.tryParse(_priceCtrl.text);
    if (product == null || qty == null || qty <= 0 || price == null || price < 0) {
      AppSnackbar.showError(context, 'يرجى اختيار منتج وإدخال كمية وسعر صحيحين.');
      return;
    }
    setState(() {
      _items.add(_DraftItem(productId: product.id, productName: product.name, unit: product.unit, quantity: qty, unitPrice: price));
      _selectedProduct = null;
      _qtyCtrl.text = '1';
      _priceCtrl.clear();
    });
  }

  void _submit() {
    if (_items.isEmpty) {
      AppSnackbar.showError(context, 'أضف صنفاً واحداً على الأقل.');
      return;
    }
    setState(() => _submitting = true);
    widget.onSubmit(
      _fmt.format(_date),
      _items.map((i) => {'product_id': i.productId, 'quantity': i.quantity, 'unit_price': i.unitPrice}).toList(),
      _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.editing != null ? 'تعديل ' : '') + (widget.type == 'goods_issued' ? 'تسليم بضاعة' : 'استرجاع بضاعة');
    final total = _items.fold(0.0, (s, i) => s + i.subtotal);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 15),
              label: Text('التاريخ: ${_fmt.format(_date)}'),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  DropdownButtonFormField<SimpleProductModel>(
                    initialValue: _selectedProduct,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المنتج'),
                    items: widget.products
                        .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                        .toList(),
                    onChanged: (p) => setState(() {
                      _selectedProduct = p;
                      _priceCtrl.text = p != null ? p.salePrice.toStringAsFixed(2) : '';
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'الكمية'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'السعر'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _addItem, icon: const Icon(Icons.add)),
                  ]),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('لا توجد أصناف مضافة', style: TextStyle(color: AppTheme.textMuted)),
                    )
                  else
                    ..._items.asMap().entries.map((e) => ListTile(
                          dense: true,
                          title: Text(e.value.productName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text('${e.value.quantity} ${e.value.unit} × ${e.value.unitPrice.toStringAsFixed(2)} = ${e.value.subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.danger),
                            onPressed: () => setState(() => _items.removeAt(e.key)),
                          ),
                        )),
                  const Divider(),
                  Text('الإجمالي: ${total.toStringAsFixed(2)}',
                      textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 10),
                  TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('حفظ'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── تسجيل دفعة — create or edit ───────────────────────────────────────────

class _PaymentFormSheet extends StatefulWidget {
  final DistributorTransactionModel? editing;
  final List<TreasuryModel> treasuries;
  final DateTime defaultDate;
  final void Function(String transactionDate, double amount, int treasuryId, String? notes) onSubmit;
  const _PaymentFormSheet({required this.editing, required this.treasuries, required this.defaultDate, required this.onSubmit});

  @override
  State<_PaymentFormSheet> createState() => _PaymentFormSheetState();
}

class _PaymentFormSheetState extends State<_PaymentFormSheet> {
  late DateTime _date;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int? _treasuryId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _date = widget.editing != null ? DateTime.parse(widget.editing!.transactionDate) : widget.defaultDate;
    _amountCtrl.text = widget.editing != null ? widget.editing!.amount.toStringAsFixed(2) : '';
    _notesCtrl.text = widget.editing?.notes ?? '';
    _treasuryId = widget.editing?.treasuryId ?? (widget.treasuries.isNotEmpty ? widget.treasuries.first.id : null);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      AppSnackbar.showError(context, 'يرجى إدخال مبلغ صحيح.');
      return;
    }
    if (_treasuryId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار الخزينة.');
      return;
    }
    setState(() => _submitting = true);
    widget.onSubmit(_fmt.format(_date), amount, _treasuryId!, _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('${widget.editing != null ? 'تعديل ' : 'تسجيل '}دفعة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 15),
            label: Text('التاريخ: ${_fmt.format(_date)}'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'المبلغ'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _treasuryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الخزينة'),
            items: widget.treasuries.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
            onChanged: (v) => setState(() => _treasuryId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
