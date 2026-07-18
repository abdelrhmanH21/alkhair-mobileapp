/// Tracks which [DelegateEvent] dispatches a screen is currently awaiting a
/// result for, keyed by [DelegateEvent.requestId], so a [DelegateState]
/// arriving on the shared `DelegateBloc` can be matched back to "is this MY
/// dispatch" — and, if so, *which kind* (an explicit fetch vs. a silent
/// PollingMixin tick vs. a user-triggered action) — instead of the ad hoc
/// `_fetchInFlight`/`_pollInFlight`/`_actionInFlight`/`_submitting` bool
/// flags every delegate screen used to hand-roll individually.
///
/// `DelegateHomePage` keeps every bottom-nav tab mounted forever inside an
/// `IndexedStack`, and several screens can additionally be pushed on top of
/// an already-mounted one — all of them share a single `DelegateBloc`
/// instance, so a state meant for one screen's request is visible to every
/// other listener on the bloc. `requestId` is the definitive way to tell
/// them apart; `RequestTracker` is just the bookkeeping around it so screens
/// don't each reinvent it slightly differently (which is how this bug class
/// kept recurring).
///
/// Usage:
/// ```dart
/// final _tracker = RequestTracker<_FetchKind>();
///
/// void _fetchSomething() {
///   final event = DelegateSomethingFetched();
///   _tracker.start(event.requestId, _FetchKind.explicit);
///   context.read<DelegateBloc>().add(event);
/// }
///
/// // in the BlocListener:
/// listener: (ctx, state) {
///   if (state is DelegateSomethingLoaded) {
///     final kind = _tracker.resolve(state.requestId);
///     if (kind == null) return; // not ours — ignore
///     ...
///   }
/// }
/// ```
class RequestTracker<K> {
  final Map<String, K> _pending = {};

  /// Registers [requestId] (from the event about to be dispatched) as
  /// outstanding, tagged with [kind] so the listener can later recover what
  /// sort of request it was.
  void start(String requestId, K kind) {
    _pending[requestId] = kind;
  }

  /// If [requestId] is one this tracker is waiting on, removes and returns
  /// its [kind] (resolving it); otherwise returns null, meaning the state
  /// this id came from belongs to some other dispatch entirely.
  K? resolve(String? requestId) {
    if (requestId == null) return null;
    return _pending.remove(requestId);
  }

  /// True if [requestId] is still outstanding (without resolving it).
  bool isPending(String requestId) => _pending.containsKey(requestId);

  /// True if any request of exactly this [kind] is currently outstanding.
  bool hasPending(K kind) => _pending.values.contains(kind);
}
