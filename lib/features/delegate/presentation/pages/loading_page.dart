import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_event.dart';
import '../bloc/delegate_state.dart';
import '../../data/models/loading_model.dart';
import 'invoice_page.dart';
import 'invoice_history_page.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({super.key});

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage> {
  LoadingModel? _currentLoading;

  // Guards confirm/status-update actions against a double-tap firing two
  // overlapping requests. Without this, a fast second tap could dispatch a
  // second DelegateLoadingConfirmed() before the button visually disables
  // (bloc state propagation lands a frame after the tap) — the SECOND
  // request always fails server-side (the loading is no longer
  // pending_pickup by then), and if that failure response happens to arrive
  // before the FIRST request's success, the user sees a spurious error right
  // before the real success navigates them away. Setting this synchronously
  // in the tap handler (not waiting for the bloc) closes that window
  // entirely, rather than just hiding whichever error shows up.
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    context.read<DelegateBloc>().add(DelegateLoadingFetched());
  }

  void _runAction(VoidCallback dispatch) {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    dispatch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التحميلة الحالية'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<DelegateBloc>().add(DelegateLoadingFetched()),
          ),
        ],
      ),
      body: BlocConsumer<DelegateBloc, DelegateState>(
        listener: (ctx, state) {
          if (state is DelegateLoadingConfirmedState) {
            setState(() {
              _currentLoading = state.loading;
              _actionInFlight = false;
            });
            AppSnackbar.showSuccess(ctx, 'تم تأكيد الاستلام. يمكنك البدء بالبيع.');
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => const InvoicePage()),
            );
          }

          if (state is DelegateLoadingStatusUpdated) {
            setState(() {
              _currentLoading = state.loading;
              _actionInFlight = false;
            });
            final label = state.loading.isInTransit
                ? 'تم تغيير الحالة إلى: في الطريق'
                : 'تم إنهاء الجولة بنجاح';
            AppSnackbar.showSuccess(ctx, label);
          }

          if (state is DelegateFailure) {
            setState(() => _actionInFlight = false);
            AppSnackbar.showError(ctx, state.message);
          }

          if (state is DelegateLoadingLoaded) {
            // No auto-navigate here: this page is now reached explicitly via
            // "عرض التفاصيل" from DelegateHomePage, so simply fetching/
            // displaying the loading must never redirect the user away from
            // the details they asked to see. The confirm action still jumps
            // to InvoicePage via DelegateLoadingConfirmedState above.
            setState(() => _currentLoading = state.loading);
          }
        },
        builder: (_, state) {
          if (state is DelegateLoading && _currentLoading == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // Full-screen error only when we have no data to show (initial fetch failed).
          // Action failures (confirm, status update) use the SnackBar from the listener
          // and keep the loading detail visible via _currentLoading.
          if (state is DelegateFailure && _currentLoading == null) {
            return _ErrorView(
              message: state.message,
              onRetry: () =>
                  context.read<DelegateBloc>().add(DelegateLoadingFetched()),
            );
          }

          if (_currentLoading == null) {
            return _EmptyLoadingView(
              onRefresh: () =>
                  context.read<DelegateBloc>().add(DelegateLoadingFetched()),
            );
          }

          final loading = _currentLoading!;
          final isBusy = _actionInFlight;

          if (loading.isInTransit) {
            return _InTransitView(
              loading: loading,
              isBusy: isBusy,
              onContinueSales: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InvoicePage()),
              ),
              onMarkCompleted: () => _runAction(() =>
                  context.read<DelegateBloc>().add(
                        DelegateLoadingStatusUpdateRequested(
                          loadingId: loading.id,
                          status: 'completed',
                        ),
                      )),
            );
          }

          if (loading.isCompleted) {
            return _CompletedView(
              loading: loading,
              onViewInvoices: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InvoiceHistoryPage()),
              ),
            );
          }

          return _LoadingView(
            loading: loading,
            isBusy: isBusy,
            onConfirm: loading.isPendingPickup
                ? () => _runAction(() =>
                    context.read<DelegateBloc>().add(DelegateLoadingConfirmed()))
                : null,
            onMarkInTransit: loading.canUpdateToInTransit
                ? () => _runAction(() => context.read<DelegateBloc>().add(
                      DelegateLoadingStatusUpdateRequested(
                        loadingId: loading.id,
                        status: 'in_transit',
                      ),
                    ))
                : null,
          );
        },
      ),
    );
  }
}

// ─── Error state ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded,
                    size: 64, color: AppTheme.danger),
              ),
              const SizedBox(height: 16),
              const Text('تعذر تحميل البيانات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

// ─── Empty state ────────────────────────────────────────────────────────────

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
            const Text('لا توجد تحميلة نشطة',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text('سيتم تعيين تحميلة لك من المدير',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
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

// ─── Pending / Accepted view ─────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final LoadingModel loading;
  final bool isBusy;
  final VoidCallback? onConfirm;
  final VoidCallback? onMarkInTransit;

  const _LoadingView({
    required this.loading,
    required this.isBusy,
    this.onConfirm,
    this.onMarkInTransit,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _HeaderCard(loading: loading),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('بنود التحميلة',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${loading.items.length} منتج',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _ItemsList(items: loading.items)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading.isPendingPickup)
                    _ActionButton(
                      onPressed: isBusy ? null : onConfirm,
                      isBusy: isBusy,
                      icon: Icons.check_circle_outline,
                      label: 'تأكيد الاستلام',
                      color: AppTheme.primary,
                    ),
                  if (loading.canUpdateToInTransit) ...[
                    const SizedBox(height: 10),
                    _ActionButton(
                      onPressed: isBusy ? null : onMarkInTransit,
                      isBusy: isBusy,
                      icon: Icons.local_shipping_outlined,
                      label: 'بدء الجولة (في الطريق)',
                      color: AppTheme.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
}

// ─── In-transit view ─────────────────────────────────────────────────────────

class _InTransitView extends StatelessWidget {
  final LoadingModel loading;
  final bool isBusy;
  final VoidCallback onContinueSales;
  final VoidCallback onMarkCompleted;

  const _InTransitView({
    required this.loading,
    required this.isBusy,
    required this.onContinueSales,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _HeaderCard(loading: loading),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_shipping_rounded,
                        size: 64, color: AppTheme.accent),
                  ),
                  const SizedBox(height: 16),
                  const Text('الجولة جارية',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('أنت حالياً في طريقك لتوصيل الطلبات',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    onPressed: onContinueSales,
                    isBusy: false,
                    icon: Icons.receipt_long_outlined,
                    label: 'متابعة المبيعات',
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 10),
                  _ActionButton(
                    onPressed: isBusy ? null : onMarkCompleted,
                    isBusy: isBusy,
                    icon: Icons.flag_rounded,
                    label: 'إنهاء الجولة',
                    color: AppTheme.secondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

// ─── Completed view ──────────────────────────────────────────────────────────

class _CompletedView extends StatelessWidget {
  final LoadingModel loading;
  final VoidCallback onViewInvoices;

  const _CompletedView({
    required this.loading,
    required this.onViewInvoices,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _HeaderCard(loading: loading),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.secondary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 64, color: AppTheme.secondary),
                  ),
                  const SizedBox(height: 16),
                  const Text('تمت الجولة',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'انتظر المدير لإتمام عملية التسوية',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _ActionButton(
                onPressed: onViewInvoices,
                isBusy: false,
                icon: Icons.history_rounded,
                label: 'عرض الفواتير',
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      );
}

// ─── Shared sub-widgets ──────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final LoadingModel loading;
  const _HeaderCard({required this.loading});

  Color get _statusColor {
    if (loading.isPendingPickup) return AppTheme.accent;
    if (loading.isAccepted) return AppTheme.primary;
    if (loading.isInTransit) return Colors.orange;
    if (loading.isCompleted) return AppTheme.secondary;
    return Colors.grey;
  }

  String get _statusLabel {
    if (loading.isPendingPickup) return 'بانتظار الاستلام';
    if (loading.isAccepted) return 'مستلمة';
    if (loading.isInTransit) return 'في الطريق';
    if (loading.isCompleted) return 'مكتملة';
    if (loading.isSettled) return 'مسوّاة';
    return loading.status;
  }

  @override
  Widget build(BuildContext context) => Card(
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
                    Text('مستودع: ${loading.warehouseName}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    if (loading.createdByName != null)
                      Text('أصدرها: ${loading.createdByName}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ItemsList extends StatelessWidget {
  final List<LoadingItemModel> items;
  const _ItemsList({required this.items});

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold)),
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
      );
}

class _ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isBusy;
  final IconData icon;
  final String label;
  final Color color;

  const _ActionButton({
    required this.onPressed,
    required this.isBusy,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: onPressed,
          icon: isBusy && onPressed == null
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(icon, size: 22),
          label: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      );
}
