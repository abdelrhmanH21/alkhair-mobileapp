import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/breakdown_models.dart';

class PenaltiesPage extends StatefulWidget {
  const PenaltiesPage({super.key});

  @override
  State<PenaltiesPage> createState() => _PenaltiesPageState();
}

class _PenaltiesPageState extends State<PenaltiesPage> {
  List<PenaltyModel>? _penalties;

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegatePenaltiesFetched());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إجمالي الجزاءات')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegatePenaltiesLoaded) {
            setState(() => _penalties = state.penalties);
          } else if (state is DelegateFailure) {
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _penalties == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final penalties = _penalties ?? [];
          if (penalties.isEmpty) {
            return const Center(
                child: Text('لا توجد جزاءات هذا الشهر.', style: TextStyle(color: Colors.grey)));
          }
          final total = penalties.fold<double>(0, (s, p) => s + p.amount);
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: AppTheme.danger.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(16),
                child: Text('إجمالي الشهر: ${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: penalties.length,
                  itemBuilder: (_, i) {
                    final p = penalties[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
                        title: Text(p.reason),
                        subtitle: Text(p.date),
                        trailing: Text(p.amount.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
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
