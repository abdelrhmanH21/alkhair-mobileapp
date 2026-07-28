import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Tracks whether the device currently has *some* network path (Wi-Fi or
/// mobile data) — not whether the API itself is reachable, just the OS-level
/// signal — so screens showing cached/possibly-stale data can decide
/// synchronously (via [isOnline], no `await`) whether to show the calm
/// "أنت غير متصل بالإنترنت" banner, both right after a failed fetch and
/// reactively if connectivity flips while the screen is still open (via
/// [onStatusChanged]).
class ConnectivityService {
  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = true;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  bool get isOnline => _isOnline;

  /// Broadcasts the new online/offline value only when it actually changes.
  Stream<bool> get onStatusChanged => _controller.stream;

  Future<void> initialize() async {
    _isOnline = _hasConnection(await _connectivity.checkConnectivity());
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(online);
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
