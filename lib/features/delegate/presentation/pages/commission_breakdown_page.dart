import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/breakdown_models.dart';

class CommissionBreakdownPage extends StatefulWidget {
  const CommissionBreakdownPage({super.key});

  @override
  State<CommissionBreakdownPage> createState() => _CommissionBreakdownPageState();
}

class _CommissionBreakdownPageState extends State<CommissionBreakdownPage> {
  List<CommissionDayModel>? _days;

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateCommissionBreakdownFetched());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العمولة المكتسبة')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateCommissionBreakdownLoaded) {
            setState(() => _days = state.days);
          } else if (state is DelegateFailure) {
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _days == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final days = _days ?? [];
          if (days.isEmpty) {
            return const Center(
                child: Text('لا توجد مبيعات هذا الشهر بعد.', style: TextStyle(color: Colors.grey)));
          }
          final totalCommission = days.fold<double>(0, (s, d) => s + d.commissionEarned);
          final totalSales = days.fold<double>(0, (s, d) => s + d.totalSales);
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: AppTheme.secondary.withValues(alpha: 0.1),
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي مبيعات الشهر: ${totalSales.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('إجمالي العمولة: ${totalCommission.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: days.length,
                  itemBuilder: (_, i) {
                    final d = days[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today_outlined, color: AppTheme.primary),
                        title: Text(d.date),
                        subtitle: Text('مبيعات اليوم: ${d.totalSales.toStringAsFixed(2)}'),
                        trailing: Text(d.commissionEarned.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
