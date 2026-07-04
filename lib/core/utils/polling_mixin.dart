import 'dart:async';
import 'package:flutter/widgets.dart';

/// Adds lightweight, silent background polling to a State: refetches on a
/// fixed interval while the widget is alive and the app is foregrounded,
/// pausing when backgrounded (via WidgetsBindingObserver) and resuming on
/// return. The mixin itself never touches the UI — implementers decide how
/// to apply a poll result, and must do so silently (no spinner, no error
/// toast for a failed poll; only user-initiated actions should surface
/// errors).
///
/// Usage:
/// ```dart
/// class _MyPageState extends State<MyPage> with PollingMixin<MyPage> {
///   @override
///   Duration get pollInterval => const Duration(seconds: 20);
///
///   @override
///   void onPoll() => context.read<MyBloc>().add(MySilentRefreshRequested());
///
///   @override
///   void initState() {
///     super.initState();
///     startPolling();
///   }
///
///   @override
///   void dispose() {
///     stopPolling();
///     super.dispose();
///   }
/// }
/// ```
mixin PollingMixin<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  _PollingLifecycleObserver? _lifecycleObserver;

  /// How often to poll while visible and foregrounded. Override to customize.
  Duration get pollInterval => const Duration(seconds: 20);

  /// Called on every tick. Implementations should dispatch a silent
  /// fetch/refresh and update the UI only if the data actually changed —
  /// never show a loading spinner or error for a poll tick.
  void onPoll();

  /// Starts polling — call once from initState() (after any dependencies
  /// the poll needs, e.g. a bloc via context, are available).
  void startPolling() {
    _lifecycleObserver ??= _PollingLifecycleObserver(
      onResumed: _resumeTimer,
      onPaused: _pauseTimer,
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    _resumeTimer();
  }

  /// Stops polling and unregisters the lifecycle observer — call from
  /// dispose() so nothing leaks.
  void stopPolling() {
    _pauseTimer();
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  void _resumeTimer() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => onPoll());
  }

  void _pauseTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

class _PollingLifecycleObserver with WidgetsBindingObserver {
  final VoidCallback onResumed;
  final VoidCallback onPaused;
  _PollingLifecycleObserver({required this.onResumed, required this.onPaused});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      onPaused();
    }
  }
}
