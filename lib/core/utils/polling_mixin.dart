import 'dart:async';
import 'package:flutter/widgets.dart';

/// Adds lightweight, silent background polling to a State: refetches on a
/// fixed interval only while the app is foregrounded AND the widget is
/// actually visible, pausing otherwise and resuming on return. The mixin
/// itself never touches the UI — implementers decide how to apply a poll
/// result, and must do so silently (no spinner, no error toast for a failed
/// poll; only user-initiated actions should surface errors).
///
/// "Visible" is read from [TickerMode] — the same signal that pauses
/// animations: Navigator/Overlay already disables it for a route covered by
/// an opaque route pushed on top, and a tab container must disable it for
/// its hidden tabs (an [IndexedStack] does NOT — it keeps every tab's
/// tickers running — so wrap each tab in `TickerMode(enabled: selected)`;
/// see DelegateHomePage). Without that, every polling tab in an
/// IndexedStack keeps polling for the whole session whichever tab is shown.
/// Becoming visible again just restarts the interval (same as returning to
/// the foreground); screens that need fresh data the moment they're shown
/// already refetch explicitly (e.g. SettlementPage's refreshTick).
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

  bool _started = false;
  bool _foreground = true;
  bool _visible = true;

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
      onForegroundChanged: (foreground) {
        _foreground = foreground;
        _sync();
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    _started = true;
    _sync();
  }

  /// Stops polling and unregisters the lifecycle observer — call from
  /// dispose() so nothing leaks.
  void stopPolling() {
    _started = false;
    _sync();
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    _sync();
  }

  /// Starts/stops the timer on state TRANSITIONS only — didChangeDependencies
  /// also fires for unrelated inherited changes (the keyboard resizing
  /// MediaQuery, ...), which must not keep resetting the interval.
  void _sync() {
    final shouldRun = _started && _foreground && _visible;
    if (shouldRun && _pollTimer == null) {
      _pollTimer = Timer.periodic(pollInterval, (_) => onPoll());
    } else if (!shouldRun && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }
}

class _PollingLifecycleObserver with WidgetsBindingObserver {
  final ValueChanged<bool> onForegroundChanged;
  _PollingLifecycleObserver({required this.onForegroundChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onForegroundChanged(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      onForegroundChanged(false);
    }
  }
}
