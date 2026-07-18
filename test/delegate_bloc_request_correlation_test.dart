import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/features/app_config/domain/repositories/app_config_repository.dart';
import 'package:alkhair_mobileapp/features/app_config/presentation/bloc/app_config_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/loading_model.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_event.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/loading_page.dart';

/// Never called: LoadingPage's confirm flow navigates to InvoicePage, which
/// reads AppConfigBloc for a price-override %, but this test never
/// dispatches AppConfigFetchRequested so fetchSettings() is never invoked.
class _FakeAppConfigRepository implements AppConfigRepository {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Minimal fake: only [getCurrentLoading] and [confirmLoading] are
/// exercised by this test. Every other method is unused by LoadingPage and
/// throws if ever called.
class _FakeDelegateRepository implements DelegateRepository {
  int getCurrentLoadingCalls = 0;
  final LoadingModel initialLoading;

  /// The 2nd+ call to getCurrentLoading (simulating a background poll
  /// dispatched from elsewhere on the shared bloc, e.g. _HomeTab) is held
  /// open until the test explicitly resolves it.
  final Completer<LoadingModel?> pollCompleter = Completer<LoadingModel?>();

  /// confirmLoading() is held open until the test explicitly resolves it,
  /// simulating the user-initiated action still being in flight.
  final Completer<LoadingModel> confirmCompleter = Completer<LoadingModel>();

  _FakeDelegateRepository(this.initialLoading);

  @override
  Future<LoadingModel?> getCurrentLoading() {
    getCurrentLoadingCalls++;
    if (getCurrentLoadingCalls == 1) {
      return Future.value(initialLoading);
    }
    return pollCompleter.future;
  }

  @override
  Future<LoadingModel> confirmLoading() => confirmCompleter.future;

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'DelegateRepository.${invocation.memberName} not used by this test');
}

void main() {
  testWidgets(
    'a background poll failure while a confirm-pickup action is in flight '
    'never surfaces as a user-facing error (closes the recurring '
    'spurious-error-after-success bug class)',
    (tester) async {
      const pendingPickup = LoadingModel(
        id: 1,
        delegateId: 7,
        warehouseId: 3,
        warehouseName: 'مستودع الاختبار',
        status: 'pending_pickup',
        items: [],
      );
      final repo = _FakeDelegateRepository(pendingPickup);
      final bloc = DelegateBloc(repo, GpsService());
      addTearDown(bloc.close);
      final appConfigBloc = AppConfigBloc(_FakeAppConfigRepository());
      addTearDown(appConfigBloc.close);

      // Providers sit ABOVE MaterialApp (mirrors app.dart's real MultiBlocProvider
      // placement) so a route pushed later, like InvoicePage after a successful
      // confirm, can still find them — a route built only under `home:` cannot.
      await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider<DelegateBloc>.value(value: bloc),
          BlocProvider<AppConfigBloc>.value(value: appConfigBloc),
        ],
        child: const MaterialApp(home: LoadingPage()),
      ));

      // Let the page's own initState fetch (1st getCurrentLoading call,
      // resolved immediately) load the pending-pickup loading.
      await tester.pump();
      await tester.pump();

      expect(find.text('تأكيد الاستلام'), findsOneWidget);

      // Start the user-initiated action (confirm pickup) — its repo call is
      // held open by confirmCompleter, simulating "still in flight".
      await tester.tap(find.text('تأكيد الاستلام'));
      await tester.pump();

      // Simulate a background poll tick — dispatched directly on the shared
      // bloc exactly as _HomeTab's PollingMixin would do from a completely
      // different, simultaneously-mounted screen — landing WHILE the confirm
      // action above is still awaiting its own result.
      bloc.add(DelegateLoadingFetched());
      await tester.pump();
      expect(repo.getCurrentLoadingCalls, 2, reason: 'the poll fetch should have reached the repo');

      // The poll fails.
      repo.pollCompleter.completeError(Exception('transient poll failure'));
      await tester.pump();
      await tester.pump();

      // The whole point of the fix: this failure belongs to the poll's own
      // requestId, not the confirm action's — it must never surface as an
      // error banner/snackbar, and must never disturb the action's own
      // "in flight" (busy) UI.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('خطأ'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets,
          reason: 'the confirm action should still show as busy/in-flight');

      // Now let the actual confirm action succeed.
      final accepted = LoadingModel(
        id: pendingPickup.id,
        delegateId: pendingPickup.delegateId,
        warehouseId: pendingPickup.warehouseId,
        warehouseName: pendingPickup.warehouseName,
        status: 'accepted',
        items: [],
      );
      repo.confirmCompleter.complete(accepted);
      await tester.pump();

      // The real success is shown correctly, unaffected by the earlier
      // ignored poll failure.
      expect(find.text('تم تأكيد الاستلام. يمكنك البدء بالبيع.'), findsOneWidget);
    },
  );
}
