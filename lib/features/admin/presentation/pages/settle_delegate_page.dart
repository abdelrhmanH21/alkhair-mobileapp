import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';
import '../bloc/admin_state.dart';
import '../../data/models/admin_models.dart';

class SettleDelegatePage extends StatefulWidget {
  final DelegateModel delegate;
  const SettleDelegatePage({super.key, required this.delegate});

  @override
  State<SettleDelegatePage> createState() => _SettleDelegatePageState();
}

class _SettleDelegatePageState extends State<SettleDelegatePage> {
  ShiftSummaryModel? _summary;
  final _cashCtrl    = TextEditingController();
  final _notesCtrl   = TextEditingController();
  final _treasuryCtrl = TextEditingController();
  int? _treasuryId;

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(AdminShiftSummaryFetched(widget.delegate.id));
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _notesCtrl.dispose();
    _treasuryCtrl.dispose();
    super.dispose();
  }

  void _settle() {
    final settlementRequestId = _summary?.settlementRequestId;
    if (settlementRequestId == null) {
      _showError('يجب أن يقوم المندوب بإرسال طلب تسليم أولاً.');
      return;
    }
    final cash = double.tryParse(_cashCtrl.text);
    if (cash == null) {
      _showError('يرجى إدخال مبلغ النقد المستلم.');
      return;
    }
    if (_treasuryId == null) {
      _showError('يرجى تحديد رقم الخزينة.');
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد اعتماد الوردية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المندوب: ${widget.delegate.name}'),
            Text('النقد الفعلي: $cash'),
            Text('الخزينة: $_treasuryId'),
            const SizedBox(height: 8),
            const Text(
              'هذه العملية لا يمكن التراجع عنها.',
              style: TextStyle(color: AppTheme.danger, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () {
              Navigator.pop(context);
              context.read<AdminBloc>().add(AdminDelegateSettled(
                    delegateId: widget.delegate.id,
                    treasuryId: _treasuryId!,
                    settlementRequestId: settlementRequestId,
                    physicalCash: cash,
                    notes: _notesCtrl.text.isNotEmpty
                        ? _notesCtrl.text
                        : null,
                  ));
            },
            child: const Text('اعتماد وتصفية الوردية'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    AppSnackbar.showError(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تصفية: ${widget.delegate.name}'),
      ),
      body: BlocConsumer<AdminBloc, AdminState>(
        listener: (ctx, state) {
          if (state is AdminShiftSummaryLoaded) {
            setState(() => _summary = state.summary);
            // Pre-fill system cash suggestion
            _cashCtrl.text =
                state.summary.totalCash.toStringAsFixed(2);
          }
          if (state is AdminSettlementSuccess) {
            AppSnackbar.showSuccess(ctx, 'تمت التصفية بنجاح');
            Navigator.of(ctx).pop();
          }
          if (state is AdminFailure) {
            _showError(state.message);
          }
        },
        builder: (_, state) {
          if (state is AdminLoading && _summary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_summary == null) {
            return const Center(
                child: Text('لم يتم تحميل ملخص الوردية'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Summary stats
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ملخص الوردية',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        _SummaryRow('عدد الفواتير',
                            _summary!.totalInvoices.toString()),
                        _SummaryRow('إجمالي المبيعات',
                            _summary!.totalGross.toStringAsFixed(2)),
                        _SummaryRow('إجمالي المرتجعات',
                            _summary!.totalReturns.toStringAsFixed(2)),
                        _SummaryRow('الصافي',
                            _summary!.totalNet.toStringAsFixed(2),
                            bold: true),
                        _SummaryRow('النقد المحصل (نظام)',
                            _summary!.totalCash.toStringAsFixed(2)),
                        _SummaryRow('ديون جديدة',
                            _summary!.totalDebtAdded.toStringAsFixed(2),
                            color: AppTheme.danger),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Remnants
                if (_summary!.truckRemnants.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('مخلفات الشاحنة (ستُعاد للمستودع)',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ..._summary!.truckRemnants.map((r) {
                            final p = r['product'] as Map? ?? {};
                            return _SummaryRow(
                              p['name'] as String? ?? '',
                              (r['current_stock_qty'] as num)
                                  .toStringAsFixed(2),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Damaged goods
                if (_summary!.damagedGoods.isNotEmpty) ...[
                  Card(
                    color: AppTheme.danger.withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('البضاعة التالفة (خسائر)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.danger)),
                          const SizedBox(height: 8),
                          ..._summary!.damagedGoods.map((d) {
                            final p = d['product'] as Map? ?? {};
                            return _SummaryRow(
                              p['name'] as String? ?? '',
                              '${(d['total_quantity'] as num).toStringAsFixed(2)} وحدة',
                              color: AppTheme.danger,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Settlement form
                if (_summary!.settlementRequestId == null)
                  Card(
                    color: AppTheme.danger.withValues(alpha: 0.08),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.danger),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'يجب أن يقوم المندوب بإرسال طلب تسليم أولاً من التطبيق قبل إمكانية التصفية.',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_summary!.settlementRequestId == null)
                  const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('بيانات التصفية',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cashCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'النقد الفعلي المستلم',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _treasuryCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'رقم الخزينة (ID)',
                            prefixIcon:
                                Icon(Icons.account_balance_outlined),
                          ),
                          onChanged: (v) =>
                              _treasuryId = int.tryParse(v),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات',
                            prefixIcon:
                                Icon(Icons.note_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: state is AdminLoading ||
                                  _summary!.settlementRequestId == null
                              ? null
                              : _settle,
                          icon: state is AdminLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Icon(Icons.verified_outlined),
                          label: const Text(
                            'اعتماد وتصفية الوردية',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _SummaryRow(this.label, this.value,
      {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.w500,
                    color: color ?? (bold ? AppTheme.primary : null))),
          ],
        ),
      );
}
