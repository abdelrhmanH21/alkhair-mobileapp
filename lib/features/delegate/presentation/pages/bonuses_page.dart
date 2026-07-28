import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/breakdown_models.dart';

class BonusesPage extends StatefulWidget {
  const BonusesPage({super.key});

  @override
  State<BonusesPage> createState() => _BonusesPageState();
}

class _BonusesPageState extends State<BonusesPage> {
  List<BonusModel>? _bonuses;

  // Same requestId-tracking convention as PenaltiesPage/AdvancesPage — this
  // page is reached from a DashboardSection card while DashboardSection
  // itself (and every other tab) stays mounted underneath, all sharing one
  // DelegateBloc.
  final _tracker = RequestTracker<bool>();

  @override
  void initState() {
    super.initState();
    final event = DelegateBonusesFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إجمالي المكافآت')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateBonusesLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _bonuses = state.bonuses);
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (_tracker.hasPending(true) && _bonuses == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final bonuses = _bonuses ?? [];
          if (bonuses.isEmpty) {
            return const Center(
                child: Text('لا توجد مكافآت هذا الشهر.', style: TextStyle(color: AppTheme.textMuted)));
          }
          final total = bonuses.fold<double>(0, (s, b) => s + b.amount);
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.green.withValues(alpha: 0.08),
                padding: const EdgeInsets.all(16),
                child: Text('إجمالي الشهر: ${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: bonuses.length,
                  itemBuilder: (_, i) {
                    final b = bonuses[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.add_circle_outline, color: Colors.green),
                        title: Text(b.reason?.isNotEmpty == true ? b.reason! : 'مكافأة'),
                        subtitle: Text(b.date),
                        trailing: Text(b.amount.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
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
