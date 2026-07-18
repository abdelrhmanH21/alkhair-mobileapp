import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../bloc/request_tracker.dart';
import '../../data/models/loading_model.dart';

class TruckStockPage extends StatefulWidget {
  const TruckStockPage({super.key});

  @override
  State<TruckStockPage> createState() => _TruckStockPageState();
}

class _TruckStockPageState extends State<TruckStockPage> {
  List<TruckStockModel> _stocks = [];

  // This tab lives forever inside DelegateHomePage's IndexedStack, sharing
  // one DelegateBloc with every other tab — without this, ANY DelegateFailure
  // from an unrelated dispatch elsewhere (e.g. _HomeTab's shipment poll)
  // would surface here as a stray SnackBar. Tracks this page's own
  // outstanding fetch by requestId instead.
  final _tracker = RequestTracker<bool>();

  void _fetch() {
    final event = DelegateTruckStockFetched();
    _tracker.start(event.requestId, true);
    context.read<DelegateBloc>().add(event);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مخزون الشاحنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetch,
          ),
        ],
      ),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateTruckStockLoaded) {
            if (_tracker.resolve(state.requestId) == null) return;
            setState(() => _stocks = state.stocks);
          } else if (state is DelegateFailure) {
            if (_tracker.resolve(state.requestId) == null) return;
            AppSnackbar.showError(ctx, state.message);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _stocks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_stocks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا يوجد مخزون في الشاحنة',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: _stocks.length,
            itemBuilder: (_, i) {
              final s = _stocks[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(s.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('الوحدة: ${s.productUnit}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        s.currentStockQty.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary),
                      ),
                      const Text('متبقي',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
