import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import '../../data/models/admin_models.dart';

/// "استلام إنتاج تام" — mirrors the web's ProductionReceivingPage.tsx:
/// pick an in-progress batch, enter the actual output quantity + warehouse
/// per product, submit to the same POST /manufacturing/{id}/complete the
/// web page uses. No planned-vs-actual yield/waste-percentage display —
/// that reporting was removed backend-wide along with the planned-quantity
/// field (see ManufacturingController).
class ReceiveProductionPage extends StatefulWidget {
  const ReceiveProductionPage({super.key});

  @override
  State<ReceiveProductionPage> createState() => _ReceiveProductionPageState();
}

class _OutputEntry {
  final ProductionOutputModel output;
  final actualCtrl = TextEditingController();
  int? warehouseId;
  _OutputEntry(this.output) {
    warehouseId = output.warehouseId;
  }
}

class _ReceiveProductionPageState extends State<ReceiveProductionPage> {
  final _remote = sl<AdminRemoteDataSource>();

  List<ProductionBatchSummaryModel> _inProgressBatches = [];
  List<ProductionBatchSummaryModel> _completedBatches = [];
  List<SimpleWarehouseModel> _warehouses = [];

  int? _selectedBatchId;
  ProductionBatchDetailModel? _batchDetail;
  List<_OutputEntry> _outputEntries = [];
  final _overheadFixedCtrl = TextEditingController();
  final _overheadVariableCtrl = TextEditingController();

  bool _loadingList = true;
  String? _error;
  bool _loadingDetail = false;
  String? _detailError;
  bool _submitting = false;
  String? _lastCompletedBatch;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _overheadFixedCtrl.dispose();
    _overheadVariableCtrl.dispose();
    for (final e in _outputEntries) {
      e.actualCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _remote.fetchInProgressBatches(),
        _remote.fetchRecentlyCompletedBatches(),
        _remote.fetchWarehouses(),
      ]);
      setState(() {
        _inProgressBatches = results[0] as List<ProductionBatchSummaryModel>;
        _completedBatches = results[1] as List<ProductionBatchSummaryModel>;
        _warehouses = (results[2] as List<SimpleWarehouseModel>)
            .where((w) => w.type == 'manufacturing')
            .toList();
        _loadingList = false;
      });
    } catch (_) {
      setState(() {
        _loadingList = false;
        _error = 'فشل تحميل التشغيلات.';
      });
    }
  }

  Future<void> _selectBatch(int id) async {
    setState(() {
      _selectedBatchId = id;
      _batchDetail = null;
      _loadingDetail = true;
      _detailError = null;
    });
    try {
      final detail = await _remote.fetchBatchDetail(id);
      setState(() {
        _batchDetail = detail;
        _outputEntries = detail.outputs.map((o) => _OutputEntry(o)).toList();
        _loadingDetail = false;
      });
    } catch (_) {
      setState(() {
        _loadingDetail = false;
        _detailError = 'فشل تحميل بيانات التشغيلة.';
      });
    }
  }

  Future<void> _submit() async {
    if (_batchDetail == null) {
      AppSnackbar.showError(context, 'اختر تشغيلة أولاً');
      return;
    }
    final hasOutput = _outputEntries
        .any((e) => (double.tryParse(e.actualCtrl.text) ?? 0) > 0);
    if (!hasOutput) {
      AppSnackbar.showError(context, 'أدخل كمية فعلية لناتج واحد على الأقل');
      return;
    }
    final missingWarehouse = _outputEntries.any((e) =>
        (double.tryParse(e.actualCtrl.text) ?? 0) > 0 &&
        e.warehouseId == null &&
        !e.output.isByproduct);
    if (missingWarehouse) {
      AppSnackbar.showError(context, 'اختر المخزن لكل ناتج لديه كمية');
      return;
    }

    setState(() => _submitting = true);
    try {
      await _remote.completeProductionBatch(
        batchId: _batchDetail!.id,
        overheadFixed: double.tryParse(_overheadFixedCtrl.text),
        overheadVariable: double.tryParse(_overheadVariableCtrl.text),
        outputs: _outputEntries
            .map((e) => {
                  'manufacturing_order_output_id': e.output.id,
                  'actual_quantity':
                      e.actualCtrl.text.isEmpty ? '0' : e.actualCtrl.text,
                  if (e.warehouseId != null) 'warehouse_id': e.warehouseId,
                })
            .toList(),
      );

      if (!mounted) return;
      final batchNum = _batchDetail!.batchNumber ?? '#${_batchDetail!.id}';
      setState(() {
        _lastCompletedBatch = batchNum;
        _submitting = false;
        _selectedBatchId = null;
        _batchDetail = null;
        _outputEntries = [];
        _overheadFixedCtrl.clear();
        _overheadVariableCtrl.clear();
      });
      AppSnackbar.showSuccess(context, 'تم استلام الإنتاج — $batchNum');
      _loadLists();
    } on DioException catch (e) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context,
          e.response?.data?['message'] as String? ?? 'فشل تسجيل الإنتاج');
    } catch (_) {
      setState(() => _submitting = false);
      AppSnackbar.showError(context, 'حدث خطأ غير متوقع');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استلام إنتاج تام')),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorView(message: _error!, onRetry: _loadLists)
              : RefreshIndicator(
                  onRefresh: _loadLists,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_lastCompletedBatch != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    AppTheme.secondary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.secondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    'تم إغلاق التشغيلة: $_lastCompletedBatch',
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      Text('١. اختيار رقم الباتشة الجارية',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_inProgressBatches.isEmpty)
                        const Text('لا توجد تشغيلات جارية.',
                            style: TextStyle(color: AppTheme.textMuted))
                      else
                        DropdownButtonFormField<int>(
                          initialValue: _selectedBatchId,
                          decoration:
                              const InputDecoration(labelText: 'رقم الباتشة'),
                          items: _inProgressBatches
                              .map((b) => DropdownMenuItem(
                                  value: b.id,
                                  child: Text(
                                      '${b.batchNumber ?? '#${b.id}'} — ${b.recipeName ?? '—'}')))
                              .toList(),
                          onChanged: (v) => v != null ? _selectBatch(v) : null,
                        ),
                      if (_loadingDetail)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (!_loadingDetail && _detailError != null)
                        AppErrorView(
                          message: _detailError!,
                          onRetry: () => _selectBatch(_selectedBatchId!),
                        ),
                      if (_batchDetail != null) ...[
                        const SizedBox(height: 16),
                        Text('الخامات المصروفة في المرحلة الأولى (للاطلاع)',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ..._batchDetail!.materials.map((m) => Card(
                              color: m.isReentry
                                  ? AppTheme.accent.withValues(alpha: 0.06)
                                  : AppTheme.cardBg,
                              child: ListTile(
                                dense: true,
                                title: Text(m.materialName ?? '—',
                                    style: const TextStyle(fontSize: 13)),
                                trailing: Text(
                                    '${m.actualQuantityUsed ?? m.quantityUsed} ${m.unit ?? ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                            )),
                        const SizedBox(height: 20),
                        Text('٢. الكميات الفعلية المنتجة',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ..._outputEntries.map((entry) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(entry.output.productName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                        ),
                                        if (entry.output.isByproduct)
                                          const Text('ثانوي',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppTheme.accent)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: entry.actualCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            decoration: const InputDecoration(
                                                labelText: 'الكمية الفعلية *',
                                                isDense: true),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: DropdownButtonFormField<int>(
                                            initialValue: entry.warehouseId,
                                            decoration: const InputDecoration(
                                                labelText: 'المخزن',
                                                isDense: true),
                                            items: _warehouses
                                                .map((w) => DropdownMenuItem(
                                                    value: w.id,
                                                    child: Text(w.name)))
                                                .toList(),
                                            onChanged: (v) => setState(
                                                () => entry.warehouseId = v),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 16),
                        ExpansionTile(
                          title: const Text('تكاليف إضافية (اختياري)',
                              style: TextStyle(fontSize: 13)),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          children: [
                            TextField(
                              controller: _overheadFixedCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'تكاليف ثابتة'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _overheadVariableCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'تكاليف متغيرة (لكل وحدة)'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                                : const Icon(Icons.inventory_2_outlined),
                            label: Text(_submitting
                                ? 'جارٍ الحفظ...'
                                : 'تسجيل الإنتاج'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text('تشغيلات مكتملة مؤخراً',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_completedBatches.isEmpty)
                        const Text('لا توجد تشغيلات مكتملة بعد.',
                            style: TextStyle(color: AppTheme.textMuted))
                      else
                        ..._completedBatches.map((b) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.check_circle_outline,
                                    color: AppTheme.secondary),
                                title: Text(b.batchNumber ?? '#${b.id}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                subtitle: Text(
                                    '${b.recipeName ?? '—'} • ${DateFormat('yyyy-MM-dd').format(b.createdAt)}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }
}
