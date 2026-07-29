import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "عملية سداد لمورد" — submits to POST /v1/mobile/admin/supplier-payment,
/// which reuses PaymentCollection (type=payment) — the exact same model
/// PaymentCollectionController::store() already uses for supplier payments
/// on the web "السداد والتحصيلات" screen.
class AdminSupplierPaymentPage extends StatefulWidget {
  const AdminSupplierPaymentPage({super.key});

  @override
  State<AdminSupplierPaymentPage> createState() =>
      _AdminSupplierPaymentPageState();
}

class _AdminSupplierPaymentPageState extends State<AdminSupplierPaymentPage> {
  final _remote = sl<AdminRemoteDataSource>();

  bool _loadingRefData = true;
  String? _error;
  List<SupplierModel> _suppliers = [];
  List<TreasuryModel> _treasuries = [];
  int? _supplierId;
  int? _treasuryId;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadRefData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    setState(() {
      _loadingRefData = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _remote.fetchSuppliers(),
        _remote.fetchTreasuries(),
      ]);
      setState(() {
        _suppliers = (results[0] as SupplierPageModel).data;
        _treasuries = results[1] as List<TreasuryModel>;
        _treasuryId = _treasuries
                .where((t) => t.isDefault)
                .map((t) => t.id)
                .firstOrNull ??
            (_treasuries.isNotEmpty ? _treasuries.first.id : null);
        _loadingRefData = false;
      });
    } catch (_) {
      setState(() {
        _loadingRefData = false;
        _error = 'فشل تحميل بيانات الشاشة.';
      });
    }
  }

  Future<void> _submit() async {
    if (_supplierId == null) {
      AppSnackbar.showError(context, 'يرجى اختيار المورد.');
      return;
    }
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
    try {
      await _remote.submitSupplierPayment(
        supplierId: _supplierId!,
        treasuryId: _treasuryId!,
        amount: amount,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _supplierId = null;
        _amountCtrl.clear();
        _notesCtrl.clear();
      });
      AppSnackbar.showSuccess(context, 'تم تسجيل السداد بنجاح.');
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context,
          e.response?.data?['message'] as String? ?? 'فشل تسجيل السداد.');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عملية سداد لمورد')),
      body: _loadingRefData
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _loadRefData)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _supplierId,
                      decoration: const InputDecoration(labelText: 'المورد'),
                      items: _suppliers
                          .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                  '${s.name}${s.balance > 0 ? ' (مديونية: ${s.balance.toStringAsFixed(0)})' : ''}')))
                          .toList(),
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'المبلغ المسدَّد', hintText: '0'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _treasuryId,
                      decoration: const InputDecoration(labelText: 'الخزينة'),
                      items: _treasuries
                          .map((t) => DropdownMenuItem(
                              value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _treasuryId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'ملاحظات (اختياري)'),
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
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded),
                        label:
                            Text(_submitting ? 'جارٍ الحفظ...' : 'حفظ السداد'),
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
