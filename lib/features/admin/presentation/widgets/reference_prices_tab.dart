import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "الأسعار المرجعية" of a مندوب حر السعر rep — read-only list of the price
/// effective today per product ("ساري من"); changes go through
/// "تعديل سعر منتج" with an "ابتداءً من" date: earlier invoices keep the price
/// of their own day, and only a past date re-prices history (previewed
/// before saving). Server: AdminFreePricingController + the
/// FreePricingReferencePriceService lookup rule.
class ReferencePricesTab extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;

  /// Injectable clock for tests; defaults to the device's local time.
  final DateTime Function() now;

  const ReferencePricesTab({super.key, required this.remote, required this.repId, this.now = DateTime.now});

  @override
  State<ReferencePricesTab> createState() => _ReferencePricesTabState();
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _fromLabel(String? effectiveFrom) => effectiveFrom ?? 'منذ البداية';

/// The preview sentence shown before saving (and reused after a delete).
String referencePriceImpactText(ReferencePriceChangeResult r) {
  if (r.invoicesRecalculated == 0) return 'لن تتغير أي فاتورة سابقة، ولن يتغير المستحق.';
  final range = r.dateFrom == r.dateTo ? 'بتاريخ ${r.dateFrom}' : 'من ${r.dateFrom} إلى ${r.dateTo}';
  return 'سيُعاد احتساب ${r.invoicesRecalculated} فاتورة سابقة ($range). '
      'المستحق: ${r.balanceBefore.toStringAsFixed(2)} ← ${r.balanceAfter.toStringAsFixed(2)}';
}

class _ReferencePricesTabState extends State<ReferencePricesTab> {
  List<ReferencePriceProductModel>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await widget.remote.fetchReferencePrices(widget.repId);
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل تحميل الأسعار المرجعية.');
    }
  }

  Future<void> _openEdit({ReferencePriceProductModel? product}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditReferencePriceSheet(
        remote: widget.remote,
        repId: widget.repId,
        products: _rows ?? const [],
        initial: product,
        today: widget.now(),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openHistory(ReferencePriceProductModel product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PriceHistorySheet(remote: widget.remote, repId: widget.repId, product: product),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return AppErrorView(message: _error!, onRetry: _load);
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openEdit(),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('تعديل سعر منتج'),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'السعر الساري اليوم لكل منتج. تغيير السعر يسري من تاريخ تختاره، والفواتير السابقة تحتفظ بسعر يومها.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ),
        const Divider(height: 16),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('لا توجد منتجات.', style: TextStyle(color: AppTheme.textMuted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _ProductPriceCard(row: rows[i], onHistory: () => _openHistory(rows[i])),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProductPriceCard extends StatelessWidget {
  final ReferencePriceProductModel row;
  final VoidCallback onHistory;
  const _ProductPriceCard({required this.row, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    row.hasPrice ? 'ساري من: ${_fromLabel(row.effectiveFrom)}' : row.unit,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  if (row.nextChangeFrom != null)
                    Text(
                      'مجدول: ${row.nextChangePrice!.toStringAsFixed(2)} من ${row.nextChangeFrom}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
            if (row.hasPrice)
              Text(row.referencePrice!.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('لم يُحدد سعر',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accent)),
              ),
            if (row.versions.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.history, size: 20),
                tooltip: 'سجل الأسعار',
                onPressed: onHistory,
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

// ─── تعديل سعر منتج ────────────────────────────────────────────────────────────

class _EditReferencePriceSheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  final List<ReferencePriceProductModel> products;
  final ReferencePriceProductModel? initial;
  final DateTime today;

  const _EditReferencePriceSheet({
    required this.remote,
    required this.repId,
    required this.products,
    required this.initial,
    required this.today,
  });

  @override
  State<_EditReferencePriceSheet> createState() => _EditReferencePriceSheetState();
}

class _EditReferencePriceSheetState extends State<_EditReferencePriceSheet> {
  final _searchCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  ReferencePriceProductModel? _product;
  late DateTime _from;
  Timer? _debounce;
  ReferencePriceChangeResult? _preview;
  String? _previewKey;
  String? _previewError;
  bool _previewLoading = false;
  bool _saving = false;

  String get _today => _ymd(widget.today);
  String get _fromYmd => _ymd(_from);
  bool get _isPast => _fromYmd.compareTo(_today) < 0;

  double? get _price {
    final p = parseNumber(_priceCtrl.text);
    if (p == null || p < 0) return null;
    // At most 2 decimals — the server rejects more.
    return ((p * 100).round() - p * 100).abs() < 1e-6 ? p : null;
  }

  String? get _currentKey =>
      _product == null || _price == null ? null : '${_product!.productId}|$_price|$_fromYmd';

  @override
  void initState() {
    super.initState();
    _product = widget.initial;
    _from = DateTime(widget.today.year, widget.today.month, widget.today.day);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    final key = _currentKey;
    setState(() {
      _previewError = null;
      _previewLoading = key != null;
    });
    if (key == null) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _runPreview(key));
  }

  Future<void> _runPreview(String key) async {
    try {
      final r = await widget.remote.previewReferencePrice(
        repId: widget.repId,
        productId: _product!.productId,
        referencePrice: _price!,
        effectiveFrom: _fromYmd,
      );
      if (!mounted || key != _currentKey) return;
      setState(() {
        _preview = r;
        _previewKey = key;
        _previewLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted || key != _currentKey) return;
      setState(() {
        _previewError = e.response?.data?['message'] as String? ?? 'تعذرت المعاينة.';
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted || key != _currentKey) return;
      setState(() {
        _previewError = 'تعذرت المعاينة.';
        _previewLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(widget.today.year + 1, widget.today.month, widget.today.day),
      helpText: 'ابتداءً من',
    );
    if (picked == null) return;
    setState(() => _from = picked);
    _schedulePreview();
  }

  Future<void> _save() async {
    if (_product == null || _price == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المنتج وإدخال سعر صحيح (رقمان عشريان على الأكثر).');
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await widget.remote.createReferencePrice(
        repId: widget.repId,
        productId: _product!.productId,
        referencePrice: _price!,
        effectiveFrom: _fromYmd,
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(context, r.message ?? 'تم حفظ السعر المرجعي.');
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل الحفظ.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final previewReady = _preview != null && _previewKey != null && _previewKey == _currentKey && !_previewLoading;
    final query = normalizeDigits(_searchCtrl.text.trim());
    final filtered = query.isEmpty
        ? widget.products
        : widget.products.where((p) => normalizeDigits(p.productName).contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('تعديل سعر منتج', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            if (product == null) ...[
              TextField(
                key: const Key('ref-price-search'),
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'ابحث عن المنتج',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('لا توجد نتائج', style: TextStyle(color: AppTheme.textMuted))),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          return ListTile(
                            dense: true,
                            title: Text(p.productName),
                            trailing: Text(p.hasPrice ? p.referencePrice!.toStringAsFixed(2) : 'لم يُحدد',
                                style: const TextStyle(color: AppTheme.textMuted)),
                            onTap: () {
                              setState(() => _product = p);
                              _schedulePreview();
                            },
                          );
                        },
                      ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            product.hasPrice
                                ? 'السعر الحالي: ${product.referencePrice!.toStringAsFixed(2)} — ساري من ${_fromLabel(product.effectiveFrom)}'
                                : 'لم يُحدد له سعر مرجعي بعد',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => _product = null);
                        _schedulePreview();
                      },
                      child: const Text('تغيير'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ref-price-value'),
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numericInputFormatters,
                decoration: const InputDecoration(labelText: 'السعر المرجعي الجديد'),
                onChanged: (_) => _schedulePreview(),
              ),
              const SizedBox(height: 10),
              InkWell(
                key: const Key('ref-price-date'),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'ابتداءً من', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  child: Text(_fromYmd),
                ),
              ),
              if (_isPast) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.accent, size: 18),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'تاريخ في الماضي: سيُطبَّق السعر بأثر رجعي على فواتير هذا المنتج من هذا التاريخ حتى السعر التالي، وقد يتغير مستحق المندوب.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                key: const Key('ref-price-preview'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _price == null
                      ? 'أدخل السعر لمعاينة الأثر قبل الحفظ.'
                      : _previewError ?? (previewReady ? referencePriceImpactText(_preview!) : 'جاري حساب الأثر...'),
                  style: TextStyle(fontSize: 12, color: _previewError != null ? AppTheme.danger : null),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _saving || !previewReady ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تأكيد الحفظ'),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ─── سجل الأسعار ───────────────────────────────────────────────────────────────

class _PriceHistorySheet extends StatefulWidget {
  final AdminRemoteDataSource remote;
  final int repId;
  final ReferencePriceProductModel product;
  const _PriceHistorySheet({required this.remote, required this.repId, required this.product});

  @override
  State<_PriceHistorySheet> createState() => _PriceHistorySheetState();
}

class _PriceHistorySheetState extends State<_PriceHistorySheet> {
  late List<ReferencePriceVersionModel> _versions = widget.product.versions;
  int? _deletingId;

  Future<void> _delete(ReferencePriceVersionModel v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سعر مرجعي'),
        content: Text('حذف السعر ${v.referencePrice.toStringAsFixed(2)} (ساري من ${_fromLabel(v.effectiveFrom)})؟'
            ' ستعود فواتير فترته إلى السعر السابق ويُعاد احتساب المستحق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingId = v.id);
    try {
      final r = await widget.remote.deleteReferencePrice(repId: widget.repId, versionId: v.id);
      if (!mounted) return;
      AppSnackbar.showSuccess(context, r.message ?? 'تم حذف السعر.');
      setState(() {
        _versions = _versions.where((x) => x.id != v.id).toList();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, e.response?.data?['message'] as String? ?? 'فشل الحذف.');
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text('سجل الأسعار — ${widget.product.productName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            if (_versions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('لا توجد أسعار.', style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _versions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final v = _versions[i];
                    final meta = [
                      if (v.createdByName != null) 'بواسطة ${v.createdByName}',
                      if (v.createdAt != null) 'في ${_ymd(v.createdAt!.toLocal())}',
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      title: Text('${v.referencePrice.toStringAsFixed(2)} — ساري من ${_fromLabel(v.effectiveFrom)}'),
                      subtitle: meta.isEmpty ? null : Text(meta, style: const TextStyle(fontSize: 11)),
                      trailing: _deletingId == v.id
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                              tooltip: 'حذف',
                              onPressed: () => _delete(v),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
    );
  }
}
