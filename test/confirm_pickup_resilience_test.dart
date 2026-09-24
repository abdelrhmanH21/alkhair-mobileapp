import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/features/app_config/domain/repositories/app_config_repository.dart';
import 'package:alkhair_mobileapp/features/app_config/presentation/bloc/app_config_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/loading_model.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/loading_page.dart';

/// The exact JSON shape the production confirm endpoint returned before the
/// backend fix (captured from the live DB): `created_by` is the raw FK
/// integer, not the {id,name} object current()/updateStatus() return.
Map<String, dynamic> _serverConfirmJson({required Object createdBy}) => {
      'id': 99,
      'delegate_id': 7,
      'warehouse_id': 3,
      'status': 'accepted',
      'created_by': createdBy,
      'loaded_at': '2026-09-23T20:56:26.000000Z',
      'warehouse': {'id': 3, 'name': 'المستودع الرئيسي'},
      'items': [
        {
          'id': 1,
          'loading_id': 99,
          'product_id': 5,
          'quantity_requested': 10,
          'quantity_confirmed': 10,
          'product': {'id': 5, 'name': 'لبن', 'unit': 'كرتونة'},
        },
      ],
    };

class _FakeAppConfigRepository implements AppConfigRepository {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// confirmLoading() runs a scripted list of attempts in order; each attempt
/// takes [delay] of (fake) time before resolving or failing.
class _ScriptedConfirmRepository implements DelegateRepository {
  final List<({Duration delay, Object? error})> script;
  int confirmCalls = 0;

  _ScriptedConfirmRepository(this.script);

  @override
  Future<LoadingModel?> getCurrentLoading() async => LoadingModel.fromJson({
        ..._serverConfirmJson(createdBy: {'id': 4, 'name': 'admin'}),
        'status': 'pending_pickup',
      });

  @override
  Future<LoadingModel> confirmLoading() async {
    final step = script[confirmCalls++];
    await Future<void>.delayed(step.delay);
    if (step.error != null) throw step.error!;
    // Parsed through the REAL fromJson with the pre-fix int created_by —
    // this is what used to throw a TypeError on every successful confirm.
    return LoadingModel.fromJson(_serverConfirmJson(createdBy: 4));
  }

  @override
  LoadingModel? getCachedLoading() => null;

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'DelegateRepository.${invocation.memberName} not used by this test');
}

DioException _timeout() => DioException(
      requestOptions: RequestOptions(path: '/delegate/loading/confirm'),
      type: DioExceptionType.receiveTimeout,
    );

Future<(DelegateBloc, _ScriptedConfirmRepository)> _pumpPage(
  WidgetTester tester,
  List<({Duration delay, Object? error})> script,
) async {
  final repo = _ScriptedConfirmRepository(script);
  final bloc = DelegateBloc(repo, GpsService());
  addTearDown(bloc.close);
  final appConfigBloc = AppConfigBloc(_FakeAppConfigRepository());
  addTearDown(appConfigBloc.close);
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<DelegateBloc>.value(value: bloc),
      BlocProvider<AppConfigBloc>.value(value: appConfigBloc),
    ],
    child: const MaterialApp(home: LoadingPage()),
  ));
  await tester.pump();
  await tester.pump();
  return (bloc, repo);
}

void main() {
  group('LoadingModel.fromJson created_by', () {
    test('tolerates the raw FK integer (pre-fix confirm response)', () {
      final m = LoadingModel.fromJson(_serverConfirmJson(createdBy: 4));
      expect(m.status, 'accepted');
      expect(m.createdByName, isNull);
      expect(m.items.single.productName, 'لبن');
    });

    test('reads the name from the {id,name} relation object', () {
      final m = LoadingModel.fromJson(
          _serverConfirmJson(createdBy: {'id': 4, 'name': 'admin'}));
      expect(m.createdByName, 'admin');
    });
  });

  testWidgets(
    'slow confirm that times out twice then succeeds never surfaces an '
    'error and ends in the correct confirmed state',
    (tester) async {
      final (_, repo) = await _pumpPage(tester, [
        (delay: const Duration(seconds: 30), error: _timeout()),
        (delay: const Duration(seconds: 30), error: _timeout()),
        (delay: const Duration(seconds: 12), error: null),
      ]);
      expect(find.text('تأكيد الاستلام'), findsOneWidget);

      await tester.tap(find.text('تأكيد الاستلام'));
      await tester.pump();

      // Walk through each timeout + backoff (2s, 4s). Before the fix, the
      // first 30s timeout would already have shown an error snackbar.
      for (final step in const [
        Duration(seconds: 30), // attempt 1 times out
        Duration(seconds: 2), // backoff
        Duration(seconds: 30), // attempt 2 times out
        Duration(seconds: 4), // backoff
      ]) {
        await tester.pump(step);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.textContaining('خطأ'), findsNothing);
        expect(find.textContaining('انتهت مهلة'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsWidgets,
            reason: 'the confirm button stays busy while retrying');
      }

      // Attempt 3 resolves successfully (with the real int created_by shape).
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();

      expect(repo.confirmCalls, 3);
      expect(find.text('تم تأكيد الاستلام. يمكنك البدء بالبيع.'), findsOneWidget);
      expect(find.textContaining('خطأ'), findsNothing);
    },
  );

  testWidgets('a genuine 4xx is not retried and is shown once', (tester) async {
    final (_, repo) = await _pumpPage(tester, [
      (
        delay: const Duration(milliseconds: 300),
        error: DioException(
          requestOptions: RequestOptions(path: '/delegate/loading/confirm'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/delegate/loading/confirm'),
            statusCode: 422,
            data: {'message': 'لا توجد بنود في هذه التحميلة.'},
          ),
        ),
      ),
    ]);

    await tester.tap(find.text('تأكيد الاستلام'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repo.confirmCalls, 1);
    expect(find.text('لا توجد بنود في هذه التحميلة.'), findsOneWidget);
  });

  testWidgets('retries are exhausted → exactly one terminal error', (tester) async {
    final (_, repo) = await _pumpPage(tester, [
      for (var i = 0; i < 3; i++) (delay: const Duration(seconds: 1), error: _timeout()),
    ]);

    await tester.tap(find.text('تأكيد الاستلام'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // attempt 1
    await tester.pump(const Duration(seconds: 2)); // backoff
    await tester.pump(const Duration(seconds: 1)); // attempt 2
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 4)); // backoff
    await tester.pump(const Duration(seconds: 1)); // attempt 3
    await tester.pump();

    expect(repo.confirmCalls, 3);
    expect(find.text('انتهت مهلة الاتصال. تحقق من الشبكة وأعد المحاولة.'), findsOneWidget);
    // Button is usable again for a manual retry.
    expect(find.text('تأكيد الاستلام'), findsOneWidget);
  });
}
