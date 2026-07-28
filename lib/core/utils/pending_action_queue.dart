import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'offline_cache_service.dart';

enum PendingActionType { sale, expense, collection }

enum PendingActionStatus { pending, syncing, failed, synced }

/// One delegate action (sale/expense/collection) queued locally while
/// offline. [payload] mirrors the exact named-argument shape the
/// corresponding `DelegateRepository.submit*()` method expects — see
/// `DelegateSyncEngine` for the exact keys read back out per [type].
/// [idempotencyKey] is generated once, at queue time, and reused for every
/// sync attempt of this same action — see the backend's
/// HandlesIdempotentSubmission trait for why that's what makes a retried
/// sync safe.
@immutable
class PendingAction {
  final String idempotencyKey;
  final PendingActionType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final PendingActionStatus status;
  final String? failureReason;

  const PendingAction({
    required this.idempotencyKey,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.status = PendingActionStatus.pending,
    this.failureReason,
  });

  PendingAction copyWith({
    PendingActionStatus? status,
    String? failureReason,
  }) {
    return PendingAction(
      idempotencyKey: idempotencyKey,
      type: type,
      payload: payload,
      createdAt: createdAt,
      status: status ?? this.status,
      // A status change away from 'failed' clears any stale reason from a
      // previous attempt instead of leaving it to confusingly linger.
      failureReason: (status != null && status != PendingActionStatus.failed) ? null : (failureReason ?? this.failureReason),
    );
  }

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'type': type.name,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'status': status.name,
        if (failureReason != null) 'failure_reason': failureReason,
      };

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
        idempotencyKey: json['idempotency_key'] as String,
        type: PendingActionType.values.byName(json['type'] as String),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['created_at'] as String),
        status: PendingActionStatus.values.byName(json['status'] as String? ?? 'pending'),
        failureReason: json['failure_reason'] as String?,
      );
}

/// A client-generated, per-action idempotency key — NOT server-assigned,
/// generated once at the moment an action is queued. A real RFC 4122 v4 UUID
/// generated locally (no network round trip, no extra `uuid` package
/// dependency — 16 cryptographically-random bytes via `Random.secure()` is
/// all v4 needs).
String generateIdempotencyKey() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xxxxxx
  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Ordered local queue of pending delegate actions, backed by
/// [OfflineCacheService]. FIFO order matters — see `DelegateSyncEngine` —
/// so this always stores/returns actions in creation order.
class PendingActionQueue {
  static const _key = 'pending_delegate_actions';
  final OfflineCacheService _cache;

  /// Live count of actions still needing attention (pending or mid-sync) —
  /// UI (the home-page badge) listens to this instead of polling.
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  PendingActionQueue(this._cache) {
    pendingCountNotifier.value = _computePendingCount();
  }

  /// Successfully-synced actions are kept (status: synced) rather than
  /// deleted immediately, so SyncStatusPage can show real "تم الإرسال"
  /// history instead of items just vanishing — but only for a day, pruned
  /// here on every read so the queue never grows unbounded.
  static const _syncedRetention = Duration(days: 1);

  List<PendingAction> getAll() {
    final raw = _cache.get(_key) as List?;
    if (raw == null) return [];
    try {
      final all = raw
          .map((e) => PendingAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final pruned = all
          .where((a) =>
              a.status != PendingActionStatus.synced ||
              DateTime.now().difference(a.createdAt) < _syncedRetention)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (pruned.length != all.length) {
        // Fire-and-forget: persist the pruned list without making every
        // read await a write. The next read is self-correcting either way.
        unawaited(_cache.set(_key, pruned.map((a) => a.toJson()).toList()));
      }
      return pruned;
    } catch (_) {
      return [];
    }
  }

  /// Anything not yet successfully delivered — pending, mid-sync, or failed
  /// (a failed item still needs the delegate's attention, arguably more
  /// urgently than a merely-pending one) — is what the badge counts.
  int _computePendingCount() =>
      getAll().where((a) => a.status != PendingActionStatus.synced).length;

  Future<void> _saveAll(List<PendingAction> actions) async {
    await _cache.set(_key, actions.map((a) => a.toJson()).toList());
    pendingCountNotifier.value = _computePendingCount();
  }

  Future<void> enqueue(PendingAction action) async {
    final all = getAll()..add(action);
    await _saveAll(all);
  }

  Future<void> updateStatus(String idempotencyKey, PendingActionStatus status, {String? failureReason}) async {
    final all = getAll();
    final index = all.indexWhere((a) => a.idempotencyKey == idempotencyKey);
    if (index == -1) return;
    all[index] = all[index].copyWith(status: status, failureReason: failureReason);
    await _saveAll(all);
  }

  /// Fully synced (or permanently discarded) — no longer tracked at all.
  Future<void> remove(String idempotencyKey) async {
    final all = getAll()..removeWhere((a) => a.idempotencyKey == idempotencyKey);
    await _saveAll(all);
  }
}
