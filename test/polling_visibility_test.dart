import 'package:alkhair_mobileapp/core/utils/polling_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PollingMixin must poll only while the app is foregrounded AND the widget
/// is visible — hidden IndexedStack tabs (wrapped in TickerMode, as
/// DelegateHomePage does) and routes covered by another route must not poll.
class _Poller extends StatefulWidget {
  const _Poller({required this.onTick});
  final VoidCallback onTick;

  @override
  State<_Poller> createState() => _PollerState();
}

class _PollerState extends State<_Poller> with PollingMixin<_Poller> {
  @override
  Duration get pollInterval => const Duration(seconds: 20);

  @override
  void onPoll() => widget.onTick();

  @override
  void initState() {
    super.initState();
    startPolling();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _Tabs extends StatefulWidget {
  const _Tabs({required this.ticks});
  final List<int> ticks;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: tab,
        children: [
          for (final (i, child) in [
            _Poller(onTick: () => widget.ticks[0]++),
            _Poller(onTick: () => widget.ticks[1]++),
          ].indexed)
            TickerMode(enabled: i == tab, child: child),
        ],
      );
}

void main() {
  testWidgets('only the visible IndexedStack tab polls', (tester) async {
    final ticks = [0, 0];
    await tester.pumpWidget(MaterialApp(home: _Tabs(ticks: ticks)));

    await tester.pump(const Duration(seconds: 61));
    expect(ticks, [3, 0]);

    tester.state<_TabsState>(find.byType(_Tabs)).setState(() {
      tester.state<_TabsState>(find.byType(_Tabs)).tab = 1;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 41));
    expect(ticks, [3, 2]);
  });

  testWidgets('a route pushed on top pauses polling until popped', (tester) async {
    var ticks = 0;
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: _Poller(onTick: () => ticks++),
    ));

    await tester.pump(const Duration(seconds: 21));
    expect(ticks, 1);

    navKey.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(ticks, 1, reason: 'covered by an opaque route');

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 21));
    expect(ticks, 2);
  });

  testWidgets('backgrounding pauses polling, resuming restarts it', (tester) async {
    var ticks = 0;
    await tester.pumpWidget(MaterialApp(home: _Poller(onTick: () => ticks++)));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(ticks, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 21));
    expect(ticks, 1);
  });

  testWidgets('unrelated dependency changes (keyboard insets) do not reset the interval', (tester) async {
    var ticks = 0;
    Widget app(double inset) => MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: inset)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(builder: (context) {
              MediaQuery.viewInsetsOf(context);
              return _Poller(onTick: () => ticks++);
            }),
          ),
        );

    await tester.pumpWidget(app(0));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(app(i.isEven ? 300 : 0));
    }
    expect(ticks, 1, reason: '25s elapsed → exactly one 20s tick despite 5 rebuilds');
  });
}
