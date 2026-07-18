import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/breakdown_models.dart';

class AdvancesPage extends StatefulWidget {
  const AdvancesPage({super.key});

  @override
  State<AdvancesPage> createState() => _AdvancesPageState();
}

class _AdvancesPageState extends State<AdvancesPage> {
  List<AdvanceModel>? _advances;

  // See PenaltiesPage's identical comment.
  final _tracker = RequestTracker<bool>();

  @override
  void initState() {
    super.initState();
    final event = DelegateAdvancesFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إجمالي السلف')),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateAdvancesLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _advances = state.advances);
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (_tracker.hasPending(true) && _advances == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final advances = _advances ?? [];
          if (advances.isEmpty) {
            return const Center(
                child: Text('لا توجد سلف هذا الشهر.', style: TextStyle(color: Colors.grey)));
          }
          final total = advances.fold<double>(0, (s, a) => s + a.amount);
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: AppTheme.accent.withValues(alpha: 0.12),
                padding: const EdgeInsets.all(16),
                child: Text('إجمالي الشهر: ${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: advances.length,
                  itemBuilder: (_, i) {
                    final a = advances[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.request_quote_outlined, color: AppTheme.accent),
                        title: Text(a.description?.isNotEmpty == true ? a.description! : a.type),
                        subtitle: Text('${a.date} — ${a.type}'),
                        trailing: Text(a.amount.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent)),
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
