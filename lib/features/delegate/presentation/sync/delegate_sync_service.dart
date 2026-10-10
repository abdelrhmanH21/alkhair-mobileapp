import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/connectivity_service.dart';
import '../../data/models/loading_model.dart';
import '../../data/models/sync_state_model.dart';
import '../../domain/repositories/delegate_repository.dart';
import '../bloc/delegate_bloc.dart';
import '../bloc/delegate_state.dart';

/// Where the delegate is in the loading lifecycle, as last confirmed by the
/// server (or seeded from the offline cache until the first sync).
enum DelegateLifecycle {
  /// Never synced and nothing cached — show a skeleton, never "none".
  unknown,
  none,
  pendingPickup,
  accepted,
  inTransit,
  completed,
  settlementRequested,
  settled,
}

/// The single source of truth for the delegate's loading / truck-stock /
/// settlement state (see docs/delegate-state-flow.md). Every delegate
/// screen reads from here instead of keeping its own copy.
///
/// It polls GET /delegate/sync-state (ETag → mostly 304s) every [interval]
/// while the app is in the foreground and a delegate is signed in, and
/// [refreshNow] runs immediately on: app resume, connectivity regained, the
/// offline queue draining, a tab/route becoming visible, any local mutation
/// seen on the DelegateBloc (confirm pickup, status change, addition
/// confirm, invoice create/edit, expense, collection, settlement submit)
/// and an FCM data message. After a settlement request it polls every
/// [fastInterval] for up to [fastWindow] while the request is pending.
/// When the probe shows a change it refetches only what moved.
///
/// Invariants:
///  - "no loading" ([DelegateLifecycle.none]) is only ever reported after a
///    successful server answer said so; until then it's [unknown].
///  - a failed/offline sync never changes the state — it only sets
///    [lastSyncFailed] (the screens' offline banner); the last known
///    loading stays on screen.
///  - the offline cache seeds the state at start-up but can never override
///    a server answer received later.
class DelegateSyncService extends ChangeNotifier with WidgetsBindingObserver {
  final DelegateRepository _repo;
  final ConnectivityService? _connectivity;
  final ValueListenable<int>? _pendingQueueCount;

  final Duration interval;
  final Duration fastInterval;
  final Duration fastWindow;

  DelegateSyncService(
    this._repo, {
    ConnectivityService? connectivity,
    ValueListenable<int>? pendingQueueCount,
    this.interval = const Duration(seconds: 8),
    this.fastInterval = const Duration(seconds: 3),
    this.fastWindow = const Duration(minutes: 2),
  })  : _connectivity = connectivity,
        _pendingQueueCount = pendingQueueCount {
    _seedFromCache();
  }

  // ── State ────────────────────────────────────────────────────────────────
  LoadingModel? _activeLoading;
  List<TruckStockModel> _truckStock = const [];
  SyncSettlementRef? _settlement;
  SyncStateModel? _snapshot;
  String? _etag;
  bool _hasSyncedOnce = false;
  bool _lastSyncFailed = false;
  bool _syncing = false;
  int _revision = 0;

  LoadingModel? get activeLoading => _activeLoading;
  List<TruckStockModel> get truckStock => _truckStock;
  List<LoadingAdditionModel> get pendingAdditions => _activeLoading?.pendingAdditions ?? const [];
  SyncSettlementRef? get settlementState => _settlement;
  String? get stockVersion => _snapshot?.stockVersion;
  bool get hasSyncedOnce => _hasSyncedOnce;
  bool get lastSyncFailed => _lastSyncFailed;
  bool get isSyncing => _syncing;

  /// Bumped on every applied change — screens with their own lists
  /// (invoice history, dashboard, settlement summary) refetch when it moves.
  int get revision => _revision;

  /// True while what's shown is last-known data rather than server-fresh.
  bool get isShowingStaleData => !_hasSyncedOnce || _lastSyncFailed;

  bool get canSell => _activeLoading?.isActiveForSales == true;
  bool get hasActiveLoading => _activeLoading != null;

  DelegateLifecycle get lifecycle {
    final loading = _activeLoading;
    if (loading == null) {
      if (!_hasSyncedOnce) return DelegateLifecycle.unknown;
      return _settlement?.isConfirmed == true ? DelegateLifecycle.settled : DelegateLifecycle.none;
    }
    final s = _settlement;
    if (s != null && s.loadingId == loading.id && s.isPending) return DelegateLifecycle.settlementRequested;
    if (loading.isPendingPickup) return DelegateLifecycle.pendingPickup;
    if (loading.isAccepted) return DelegateLifecycle.accepted;
    if (loading.isInTransit) return DelegateLifecycle.inTransit;
    if (loading.isCompleted) return DelegateLifecycle.completed;
    return DelegateLifecycle.unknown;
  }

  void _seedFromCache() {
    _activeLoading = _safe(_repo.getCachedLoading);
    _truckStock = _safe(_repo.getCachedTruckStock) ?? const [];
  }

  static T? _safe<T>(T? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  // ── Polling lifecycle ────────────────────────────────────────────────────
  bool _started = false;
  bool _foreground = true;
  Timer? _timer;
  DateTime? _fastUntil;
  StreamSubscription<bool>? _connectivitySub;
  int _lastQueueCount = 0;

  bool get isPolling => _timer != null;

  /// Called when the delegate home mounts (a delegate is signed in).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = _connectivity?.onStatusChanged.listen((online) {
      if (online) refreshNow();
    });
    _lastQueueCount = _pendingQueueCount?.value ?? 0;
    _pendingQueueCount?.addListener(_onQueueCountChanged);
    refreshNow();
  }

  /// Called when the delegate home unmounts (logout). Clears in-memory
  /// state so a different account never sees the previous one's.
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _pendingQueueCount?.removeListener(_onQueueCountChanged);
    _timer?.cancel();
    _timer = null;
    _fastUntil = null;
    _snapshot = null;
    _etag = null;
    _settlement = null;
    _hasSyncedOnce = false;
    _lastSyncFailed = false;
    _seedFromCache();
  }

  void _onQueueCountChanged() {
    final count = _pendingQueueCount!.value;
    // The offline queue just delivered something — the server state moved.
    if (count < _lastQueueCount) refreshNow();
    _lastQueueCount = count;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      refreshNow();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Poll faster for a bounded time — used while waiting for the admin
  /// (e.g. right after a settlement request is submitted).
  void accelerate([Duration? window]) {
    _fastUntil = DateTime.now().add(window ?? fastWindow);
    _schedule();
  }

  Duration get currentInterval {
    final fastUntil = _fastUntil;
    if (fastUntil != null && DateTime.now().isBefore(fastUntil)) return fastInterval;
    return interval;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_foreground) return;
    _timer = Timer(currentInterval, refreshNow);
  }

  // ── Sync ─────────────────────────────────────────────────────────────────
  Future<void>? _inFlight;
  bool _rerun = false;
  bool _forceNext = false;

  /// Syncs now. Concurrent calls coalesce into the in-flight one plus at
  /// most one follow-up, so a burst of triggers costs one or two probes.
  /// [force] skips the ETag and refetches loading + stock regardless.
  Future<void> refreshNow({bool force = false}) {
    if (force) _forceNext = true;
    final inFlight = _inFlight;
    if (inFlight != null) {
      _rerun = true;
      return inFlight;
    }
    return _inFlight = _runLoop();
  }

  Future<void> _runLoop() async {
    try {
      do {
        _rerun = false;
        final force = _forceNext;
        _forceNext = false;
        await _syncOnce(force: force);
      } while (_rerun);
    } finally {
      _inFlight = null;
      _schedule();
    }
  }

  Future<void> _syncOnce({required bool force}) async {
    _syncing = true;
    try {
      final result = await _repo.getSyncState(etag: force ? null : _etag);
      if (result.notModified && _snapshot != null) {
        _etag = result.etag;
        _markSuccess(changed: false);
        return;
      }
      final next = result.state;
      if (next == null) throw StateError('sync-state returned no body');

      final prev = _snapshot;
      final loadingMoved = force ||
          prev == null ||
          prev.loading != next.loading ||
          !listEquals(prev.pendingAdditionIds, next.pendingAdditionIds) ||
          next.loading?.id != _activeLoading?.id ||
          next.loading?.status != _activeLoading?.status;
      final stockMoved = force || prev == null || prev.stockVersion != next.stockVersion;

      // Refetch everything that moved BEFORE committing anything: a failed
      // refetch leaves the old state (and old ETag) untouched, so the next
      // tick retries instead of half-applying.
      var loading = _activeLoading;
      if (loadingMoved) {
        // The repository caches the answer — including clearing the cache
        // on a confirmed "none" (the only path allowed to write "none").
        loading = await _repo.getCurrentLoading();
      }
      var stock = _truckStock;
      if (stockMoved) {
        stock = await _repo.getTruckStock();
        // Best-effort: keeps the sell picker's offline cache current.
        unawaited(_repo.getSellableProducts().then((_) {}, onError: (_) {}));
      }

      final changed = loadingMoved || stockMoved || _settlement != next.settlementRequest || !_hasSyncedOnce;
      _snapshot = next;
      _etag = result.etag;
      _activeLoading = loading;
      _truckStock = stock;
      _settlement = next.settlementRequest;
      if (_settlement?.isPending != true) {
        // Nothing left to wait for — drop back to the normal cadence.
        _fastUntil = null;
      }
      _markSuccess(changed: changed);
    } catch (e) {
      debugPrint('[delegate-sync] failed: $e');
      final wasFailed = _lastSyncFailed;
      _lastSyncFailed = true;
      _syncing = false;
      if (!wasFailed) notifyListeners();
    }
  }

  void _markSuccess({required bool changed}) {
    final flagChanged = _lastSyncFailed || !_hasSyncedOnce;
    _syncing = false;
    _lastSyncFailed = false;
    _hasSyncedOnce = true;
    if (changed) _revision++;
    if (changed || flagChanged) notifyListeners();
  }

  /// A server response that carries the full current loading (confirm
  /// pickup, status change, addition confirm, explicit fetch) — applied at
  /// once, without waiting for the next poll.
  void applyServerLoading(LoadingModel? loading) {
    _activeLoading = loading;
    _hasSyncedOnce = true;
    _revision++;
    notifyListeners();
  }

  void applyServerTruckStock(List<TruckStockModel> stock) {
    _truckStock = stock;
    _revision++;
    notifyListeners();
  }

  /// Wires the service to the shared DelegateBloc: server answers carrying
  /// the loading/stock are applied immediately, and every local mutation
  /// triggers an immediate sync. User-initiated actions keep their own
  /// RequestTracker flow — this only observes their outcomes.
  StreamSubscription<DelegateState> bindBloc(Stream<DelegateState> states) {
    return states.listen((state) {
      if (state is DelegateLoadingConfirmedState) {
        applyServerLoading(state.loading);
        refreshNow();
      } else if (state is DelegateLoadingStatusUpdated) {
        applyServerLoading(state.loading);
        refreshNow();
      } else if (state is DelegateLoadingAdditionConfirmedState) {
        if (state.loading != null) applyServerLoading(state.loading);
        refreshNow();
      } else if (state is DelegateLoadingLoaded) {
        applyServerLoading(state.loading);
      } else if (state is DelegateTruckStockLoaded) {
        applyServerTruckStock(state.stocks);
      } else if (state is DelegateSettlementRequestSubmittedState) {
        accelerate();
        refreshNow();
      } else if (state is DelegateInvoiceSubmittedState ||
          state is DelegateInvoiceUpdatedState ||
          state is DelegateExpenseSubmittedState ||
          state is DelegateCustomerCollectionSubmittedState ||
          state is DelegateExpenseRecordUpdatedState ||
          state is DelegateExpenseRecordDeletedState ||
          state is DelegateCustomerCollectionRecordUpdatedState ||
          state is DelegateCustomerCollectionRecordDeletedState) {
        refreshNow();
      }
    });
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Makes the [DelegateSyncService] reachable from every delegate screen —
/// including pushed routes, which is why it sits above the MaterialApp's
/// Navigator — and binds it to the DelegateBloc above it.
class DelegateSyncScope extends StatefulWidget {
  final DelegateSyncService service;
  final Widget child;
  const DelegateSyncScope({super.key, required this.service, required this.child});

  /// Null when no scope is mounted (isolated widget tests).
  static DelegateSyncService? maybeOf(BuildContext context, {bool listen = true}) => listen
      ? context.dependOnInheritedWidgetOfExactType<_DelegateSyncInherited>()?.notifier
      : context.getInheritedWidgetOfExactType<_DelegateSyncInherited>()?.notifier;

  static DelegateSyncService of(BuildContext context, {bool listen = true}) {
    final service = maybeOf(context, listen: listen);
    assert(service != null, 'No DelegateSyncScope above this widget');
    return service!;
  }

  @override
  State<DelegateSyncScope> createState() => _DelegateSyncScopeState();
}

class _DelegateSyncScopeState extends State<DelegateSyncScope> {
  StreamSubscription<DelegateState>? _sub;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _sub?.cancel();
    DelegateBloc? bloc;
    try {
      bloc = context.read<DelegateBloc>();
    } catch (_) {
      bloc = null; // no DelegateBloc above (e.g. an isolated test)
    }
    _sub = bloc == null ? null : widget.service.bindBloc(bloc.stream);
  }

  @override
  void didUpdateWidget(covariant DelegateSyncScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) _bind();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DelegateSyncInherited(notifier: widget.service, child: widget.child);
}

class _DelegateSyncInherited extends InheritedNotifier<DelegateSyncService> {
  const _DelegateSyncInherited({required super.notifier, required super.child});
}

/// For screens that own a list of their own (invoice history, dashboard,
/// settlement summary) but must refresh it whenever the shared delegate
/// state moves (a sale, a top-up, a settlement confirmation, ...): calls
/// [onDelegateStateChanged] each time [DelegateSyncService.revision] moves.
/// A no-op when no DelegateSyncScope is mounted (isolated widget tests).
mixin DelegateSyncRefetchMixin<T extends StatefulWidget> on State<T> {
  DelegateSyncService? _refetchSync;
  int _refetchSeenRevision = -1;

  void onDelegateStateChanged();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sync = DelegateSyncScope.maybeOf(context, listen: false);
    if (sync == _refetchSync) return;
    _refetchSync?.removeListener(_onRefetchSyncChanged);
    _refetchSync = sync?..addListener(_onRefetchSyncChanged);
    _refetchSeenRevision = sync?.revision ?? -1;
  }

  void _onRefetchSyncChanged() {
    final sync = _refetchSync;
    if (sync == null || !mounted || sync.revision == _refetchSeenRevision) return;
    _refetchSeenRevision = sync.revision;
    onDelegateStateChanged();
  }

  @override
  void dispose() {
    _refetchSync?.removeListener(_onRefetchSyncChanged);
    super.dispose();
  }
}
