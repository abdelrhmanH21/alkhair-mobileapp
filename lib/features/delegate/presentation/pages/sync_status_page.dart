import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_snackbar.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../data/sync/delegate_sync_engine.dart';

/// Phase 4.1: tapping the pending-actions badge (delegate_home_page.dart)
/// lands here — every queued action (pending/syncing/failed/synced) with a
/// retry button for failed items and a way to discard one permanently.
class SyncStatusPage extends StatefulWidget {
  const SyncStatusPage({super.key});

  @override
  State<SyncStatusPage> createState() => _SyncStatusPageState();
}

class _SyncStatusPageState extends State<SyncStatusPage> {
  late List<PendingAction> _actions;

  @override
  void initState() {
    super.initState();
    _refresh();
    sl<PendingActionQueue>().pendingCountNotifier.addListener(_refresh);
  }

  @override
  void dispose() {
    sl<PendingActionQueue>().pendingCountNotifier.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _actions = sl<PendingActionQueue>().getAll().reversed.toList());
  }

  Future<void> _syncNow() async {
    if (!sl<ConnectivityService>().isOnline) {
      AppSnackbar.showInfo(context, 'لا يوجد اتصال بالإنترنت حاليًا.');
      return;
    }
    await sl<DelegateSyncEngine>().syncNow();
    _refresh();
  }

  Future<void> _retry(PendingAction action) async {
    await sl<PendingActionQueue>().updateStatus(action.idempotencyKey, PendingActionStatus.pending);
    _refresh();
    await _syncNow();
  }

  Future<void> _discard(PendingAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تجاهل العملية نهائيًا؟'),
        content: const Text('لن يتم إرسال هذه العملية أبدًا ولا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تجاهل نهائيًا'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await sl<PendingActionQueue>().remove(action.idempotencyKey);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة المزامنة'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: sl<DelegateSyncEngine>().isSyncingNotifier,
            builder: (_, isSyncing, __) => IconButton(
              icon: isSyncing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync_rounded),
              tooltip: 'مزامنة الآن',
              onPressed: isSyncing ? null : _syncNow,
            ),
          ),
        ],
      ),
      body: _actions.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد عمليات بانتظار المزامنة',
                      style: TextStyle(color: AppTheme.textMuted)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _actions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _PendingActionCard(
                action: _actions[i],
                onRetry: () => _retry(_actions[i]),
                onDiscard: () => _discard(_actions[i]),
              ),
            ),
    );
  }
}

class _PendingActionCard extends StatelessWidget {
  final PendingAction action;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  const _PendingActionCard({
    required this.action,
    required this.onRetry,
    required this.onDiscard,
  });

  IconData get _typeIcon {
    switch (action.type) {
      case PendingActionType.sale:
        return Icons.point_of_sale_rounded;
      case PendingActionType.expense:
        return Icons.payments_outlined;
      case PendingActionType.collection:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String get _typeLabel {
    switch (action.type) {
      case PendingActionType.sale:
        return 'فاتورة بيع';
      case PendingActionType.expense:
        return 'مصروف';
      case PendingActionType.collection:
        return 'تحصيل من عميل';
    }
  }

  /// Derived from the payload — each action type's payload shape differs
  /// (see where each is enqueued: invoice_page.dart / transactions_page.dart)
  /// so this is the one place that knows how to summarize all three.
  String get _summary {
    final p = action.payload;
    switch (action.type) {
      case PendingActionType.sale:
        final itemCount = (p['sales_items'] as List? ?? []).length;
        return '${p['client_name'] ?? ''} — $itemCount صنف';
      case PendingActionType.expense:
        final amount = (p['amount'] as num?)?.toStringAsFixed(2) ?? '';
        return '${p['description'] ?? ''} — $amount ج.م';
      case PendingActionType.collection:
        final amount = (p['amount'] as num?)?.toStringAsFixed(2) ?? '';
        return '${p['customer_name'] ?? ''} — $amount ج.م';
    }
  }

  Color get _statusColor {
    switch (action.status) {
      case PendingActionStatus.pending:
        return AppTheme.accent;
      case PendingActionStatus.syncing:
        return AppTheme.primary;
      case PendingActionStatus.failed:
        return AppTheme.danger;
      case PendingActionStatus.synced:
        return AppTheme.secondary;
    }
  }

  String get _statusLabel {
    switch (action.status) {
      case PendingActionStatus.pending:
        return 'بانتظار الإرسال';
      case PendingActionStatus.syncing:
        return 'جارٍ الإرسال...';
      case PendingActionStatus.failed:
        return 'فشل الإرسال';
      case PendingActionStatus.synced:
        return 'تم الإرسال';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_typeIcon, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_typeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_summary, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_statusLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(action.createdAt),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
            if (action.status == PendingActionStatus.failed) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  action.failureReason ?? 'فشل الإرسال لسبب غير معروف.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.danger),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                      onPressed: onDiscard,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('تجاهل'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
