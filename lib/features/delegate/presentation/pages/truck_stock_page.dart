import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/loading_model.dart';

class TruckStockPage extends StatefulWidget {
  const TruckStockPage({super.key});

  @override
  State<TruckStockPage> createState() => _TruckStockPageState();
}

class _TruckStockPageState extends State<TruckStockPage> {
  List<TruckStockModel> _stocks = [];

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateTruckStockFetched());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مخزون الشاحنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<DelegateBloc>().add(DelegateTruckStockFetched()),
          ),
        ],
      ),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateTruckStockLoaded) {
            setState(() => _stocks = state.stocks);
          } else if (state is DelegateFailure) {
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
