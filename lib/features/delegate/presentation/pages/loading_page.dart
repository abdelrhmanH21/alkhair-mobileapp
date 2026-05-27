import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/loading_model.dart';
import 'invoice_page.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  LoadingModel? _currentLoading;

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateLoadingFetched());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التحميلة الحالية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<DelegateBloc>().add(DelegateLoadingFetched()),
          ),
        ],
      ),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateLoadingConfirmedState) {
            setState(() => _currentLoading = state.loading);
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('تم تأكيد الاستلام. يمكنك البدء بالبيع.'),
              backgroundColor: AppTheme.secondary,
            ));
            // Navigate to sales panel
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => const InvoicePage()),
            );
          }
          if (state is DelegateFailure) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.danger,
            ));
          }
          if (state is DelegateLoadingLoaded) {
            setState(() => _currentLoading = state.loading);
            // If already accepted, jump to sales
            if (state.loading?.isAccepted == true) {
              final nav = Navigator.of(ctx);
              Future.microtask(() => nav.pushReplacement(
                    MaterialPageRoute(builder: (_) => const InvoicePage()),
                  ));
            }
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_currentLoading == null) {
            return _EmptyLoadingView(
              onRefresh: () =>
                  context.read<DelegateBloc>().add(DelegateLoadingFetched()),
            );
          }

          return _LoadingView(
            loading: _currentLoading!,
            onConfirm: state is DelegateLoading
                ? null
                : () => context.read<DelegateBloc>().add(DelegateLoadingConfirmed()),
          );
        },
      ),
    );
  }
}

class _EmptyLoadingView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyLoadingView({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'لا توجد تحميلة نشطة',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'سيتم تعيين تحميلة لك من المدير',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
          ],
        ),
      );
}

class _LoadingView extends StatelessWidget {
  final LoadingModel loading;
  final VoidCallback? onConfirm;
  const _LoadingView({required this.loading, this.onConfirm});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          // Header info card
          Card(
            margin: const EdgeInsets.all(12),
            color: AppTheme.primary,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warehouse_outlined, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مستودع: ${loading.warehouseName}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        if (loading.createdByName != null)
                          Text(
                            'أصدرها: ${loading.createdByName}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: loading.isPendingPickup
                          ? AppTheme.accent
                          : Colors.greenAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      loading.isPendingPickup ? 'بانتظار الاستلام' : 'مستلمة',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Items list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('بنود التحميلة',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${loading.items.length} منتج',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: loading.items.length,
              itemBuilder: (_, i) {
                final item = loading.items[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(item.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('الوحدة: ${item.productUnit}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.quantityRequested.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary),
                        ),
                        const Text('كمية',
                            style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Confirm button
          if (loading.isPendingPickup)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: onConfirm == null
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ))
                        : const Icon(Icons.check_circle_outline, size: 24),
                    label: Text(
                      onConfirm == null ? 'جارٍ التأكيد...' : 'تأكيد الاستلام',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
