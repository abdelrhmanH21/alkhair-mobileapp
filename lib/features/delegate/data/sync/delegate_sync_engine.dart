import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/utils/connectivity_service.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../domain/repositories/delegate_repository.dart';

/// Phase 3 offline-sync engine: submits queued delegate actions (sales,
/// expenses, customer collections) to the real endpoints once connectivity
/// is available, one at a time, in the order they were queued.
///
/// Triggered by three independent sources — app foreground resume
/// (DelegateHomePage's WidgetsBindingObserver), connectivity being restored
/// ([ConnectivityService.onStatusChanged]), and a manual "مزامنة الآن"
/// button (SyncStatusPage) — all of which just call [syncNow]; [_syncing]
/// guards against them overlapping (checked synchronously before any
/// `await`, so it's safe even if two triggers fire back-to-back on the same
/// event loop turn).
///
/// FIFO order matters, not just for fairness: a later queued sale for the
/// same product may only be valid once an EARLIER queued sale for that same
/// product has actually been deducted server-side. Processing strictly in
/// creation order — and stopping the whole pass on a network-type failure
/// rather than skipping ahead — is what keeps that dependency correct.
class DelegateSyncEngine {
  final PendingActionQueue _queue;
  final DelegateRepository _repo;
  final ConnectivityService _connectivity;

  bool _syncing = false;
  StreamSubscription<bool>? _connectivitySubscription;

  /// True while a sync pass is actively running — UI (the pending badge/
  /// sync status page) can show a spinner instead of a static count.
  final ValueNotifier<bool> isSyncingNotifier = ValueNotifier(false);

  DelegateSyncEngine(this._queue, this._repo, this._connectivity);

  /// Call once at app startup (see service_locator.dart). Subscribes to
  /// connectivity changes and attempts an immediate sync in case actions
  /// were already queued from a previous session and the app happens to
  /// open already online.
  void initialize() {
    _connectivitySubscription ??= _connectivity.onStatusChanged.listen((online) {
      if (online) syncNow();
    });
    if (_connectivity.isOnline) {
      syncNow();
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    if (!_connectivity.isOnline) return;

    _syncing = true;
    isSyncingNotifier.value = true;
    try {
      // getAll() already returns creation-order (FIFO) — see
      // PendingActionQueue.getAll(). Includes 'syncing' as well as
      // 'pending': a prior sync attempt that never got to update the status
      // (app killed mid-request) must not get stuck forever.
      final actions = _queue
          .getAll()
          .where((a) => a.status == PendingActionStatus.pending || a.status == PendingActionStatus.syncing)
          .toList();

      for (final action in actions) {
        if (!_connectivity.isOnline) break;
        final shouldContinue = await _syncOne(action);
        if (!shouldContinue) break;
      }
    } finally {
      _syncing = false;
      isSyncingNotifier.value = false;
    }
  }

  /// Returns true if the pass should continue to the next queued action,
  /// false if it should stop here (network-type failure — order must be
  /// preserved, later actions may depend on this one's not-yet-known
  /// server-side effect).
  Future<bool> _syncOne(PendingAction action) async {
    await _queue.updateStatus(action.idempotencyKey, PendingActionStatus.syncing);
    try {
      switch (action.type) {
        case PendingActionType.sale:
          await _syncSale(action);
          break;
        case PendingActionType.expense:
          await _syncExpense(action);
          break;
        case PendingActionType.collection:
          await _syncCollection(action);
          break;
      }
      // Kept (not deleted) so SyncStatusPage can show real "تم الإرسال"
      // confirmation — see PendingActionQueue's pruning of old synced rows.
      await _queue.updateStatus(action.idempotencyKey, PendingActionStatus.synced);
      return true;
    } on DioException catch (e) {
      if (_isBusinessRejection(e)) {
        // The server definitively processed and rejected this specific
        // request (e.g. the oversell-race case: real stock, at sync time,
        // is no longer enough) — its effect (or lack of one) is now a fixed
        // fact, so later queued actions can safely be evaluated against
        // that same fixed state. Mark failed and let the delegate decide
        // (see SyncStatusPage) rather than silently dropping it or retrying
        // forever.
        await _queue.updateStatus(
          action.idempotencyKey,
          PendingActionStatus.failed,
          failureReason: _extractMessage(e),
        );
        return true;
      }
      // Network/timeout/unclear server error — leave as 'pending' (reset
      // from 'syncing' above) and stop this whole pass; retried on the next
      // trigger. We don't know whether this request actually landed or not,
      // so later actions must wait rather than risk running out of order.
      await _queue.updateStatus(action.idempotencyKey, PendingActionStatus.pending);
      return false;
    } catch (_) {
      await _queue.updateStatus(action.idempotencyKey, PendingActionStatus.pending);
      return false;
    }
  }

  /// Only a real 422 (Laravel validation/business-rule abort — see
  /// DelegateInvoiceController::store's abort(422, ...) calls and
  /// DelegateTruckStock::deductStock) counts as "the server looked at this
  /// specific request and rejected it". Everything else (no response at
  /// all, timeouts, 5xx) is treated as transient/unclear and left pending.
  bool _isBusinessRejection(DioException e) => e.response?.statusCode == 422;

  String _extractMessage(DioException e) {
    final serverMessage = e.response?.data?['message'] as String?;
    if (serverMessage != null && serverMessage.isNotEmpty) return serverMessage;
    return 'فشل الطلب.';
  }

  Future<void> _syncSale(PendingAction action) async {
    final p = action.payload;
    final salesItems = ((p['sales_items'] as List?) ?? [])
        .map((e) => {
              'product_id': e['product_id'],
              'qty': e['qty'],
              'unit_price': e['unit_price'],
            })
        .toList();
    final returnedItems = ((p['returned_items'] as List?) ?? [])
        .map((e) => {
              'product_id': e['product_id'],
              'qty': e['qty'],
              'unit_price': e['unit_price'],
              'status': e['condition'],
              'refund_method': e['refund_method'] ?? 'cash',
              if (e['replacement_product_id'] != null)
                'replacement_product_id': e['replacement_product_id'],
              if (e['replacement_quantity'] != null)
                'replacement_quantity': e['replacement_quantity'],
              if (e['replacement_unit_price'] != null)
                'replacement_unit_price': e['replacement_unit_price'],
            })
        .toList();

    await _repo.submitInvoice(
      clientId: p['client_id'] as int,
      salesItems: salesItems,
      returnedItems: returnedItems,
      cashReceived: (p['cash_received'] as num).toDouble(),
      discountAmount: (p['discount_amount'] as num?)?.toDouble() ?? 0,
      latitude: (p['latitude'] as num?)?.toDouble(),
      longitude: (p['longitude'] as num?)?.toDouble(),
      idempotencyKey: action.idempotencyKey,
    );

    // Replace the optimistic local deduction with the real, authoritative
    // post-sync numbers — fire-and-forget, never blocks the sync loop.
    unawaited(_repo.getTruckStock());
    unawaited(_repo.getSellableProducts());
  }

  Future<void> _syncExpense(PendingAction action) async {
    final p = action.payload;
    await _repo.submitExpense(
      amount: (p['amount'] as num).toDouble(),
      description: p['description'] as String,
      categoryId: p['category_id'] as int?,
      notes: p['notes'] as String?,
      idempotencyKey: action.idempotencyKey,
    );
  }

  Future<void> _syncCollection(PendingAction action) async {
    final p = action.payload;
    await _repo.submitCustomerCollection(
      customerId: p['customer_id'] as int,
      amount: (p['amount'] as num).toDouble(),
      paymentMethod: p['payment_method'] as String,
      notes: p['notes'] as String?,
      idempotencyKey: action.idempotencyKey,
    );
  }
}
