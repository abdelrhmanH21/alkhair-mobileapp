import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/state_views.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/settlement_summary_model.dart';

/// "تسليم" tab: the delegate declares end-of-shift cash + e-wallet totals.
/// The good/damaged goods breakdown is computed server-side (same logic the
/// admin sees on the shift-summary screen) — the delegate only enters the
/// two amounts, never re-types numbers that already exist on the server.
class SettlementPage extends StatefulWidget {
  const SettlementPage({super.key});

  @override
  State<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends State<SettlementPage> {
  SettlementSummaryModel? _summary;
  String? _summaryError;
  bool _submitting = false;
  bool _submitted = false;
  String? _submittedMessage;

  final _cashCtrl = TextEditingController(text: '0');
  final _walletCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _walletCtrl.dispose();
    super.dispose();
  }

  void _fetchSummary() {
    setState(() => _summaryError = null);
    context.read<DelegateBloc>().add(DelegateSettlementSummaryRequested());
  }

  void _submit() {
    final cash = double.tryParse(_cashCtrl.text) ?? -1;
    final wallet = double.tryParse(_walletCtrl.text) ?? -1;
    if (cash < 0 || wallet < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى إدخال مبالغ صحيحة للنقدي والمحفظة الإلكترونية.'),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _submitting = true);
    context.read<DelegateBloc>().add(DelegateSettlementRequestSubmitted(
          cashAmount: cash,
          walletAmount: wallet,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسليم الوردية')),
      body: BlocListener<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateSettlementSummaryLoaded) {
            setState(() {
              _summary = state.summary;
              _summaryError = null;
            });
          } else if (state is DelegateSettlementRequestSubmittedState) {
            setState(() {
              _submitting = false;
              _submitted = true;
              _submittedMessage = state.message;
            });
          } else if (state is DelegateFailure) {
            if (_submitting) {
              setState(() => _submitting = false);
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.danger,
              ));
            } else if (_summary == null) {
              setState(() => _summaryError = state.message);
            }
          }
        },
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_submitted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 64, color: AppTheme.secondary),
              const SizedBox(height: 16),
              Text(_submittedMessage ?? 'تم إرسال طلب التسليم.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('بانتظار تأكيد الإدارة لإتمام تصفية الوردية.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_summary == null && _summaryError == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_summary == null && _summaryError != null) {
      return AppErrorView(
        title: 'تعذر تحميل بيانات الوردية',
        message: _summaryError!,
        danger: false,
        onRetry: _fetchSummary,
      );
    }

    final summary = _summary!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(summary: summary),
          const SizedBox(height: 16),
          Text('بيانات التسليم', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _cashCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'نقدي',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _walletCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'محفظة إلكترونية',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_submitting ? 'جاري الإرسال...' : 'إرسال طلب التسليم'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final SettlementSummaryModel summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: AppTheme.elevationMed,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ملخص الوردية', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Stat(label: 'صافي المبيعات', value: summary.totalNet)),
                Expanded(child: _Stat(label: 'النقدي (نظام)', value: summary.totalCash)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _Stat(label: 'مرتجعات', value: summary.totalReturns)),
                Expanded(child: _Stat(label: 'دين مضاف', value: summary.totalDebtAdded)),
              ],
            ),
            if (summary.damagedGoods.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.report_problem_outlined, size: 16, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Text('بضاعة تالفة', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              ...summary.damagedGoods.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(d.productName)),
                        Text('${d.totalQuantity.toStringAsFixed(2)} — ${d.totalValue.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )),
            ],
            if (summary.truckRemnants.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text('باقي في الشاحنة', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              ...summary.truckRemnants.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(r.productName)),
                        Text('${r.quantity.toStringAsFixed(2)} ${r.productUnit}'),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value.toStringAsFixed(2),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.primary)),
        ],
      );
}
