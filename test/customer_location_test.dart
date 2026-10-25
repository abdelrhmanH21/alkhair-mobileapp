import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alkhair_mobileapp/core/utils/connectivity_service.dart';
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/location_service.dart';
import 'package:alkhair_mobileapp/core/utils/offline_cache_service.dart';
import 'package:alkhair_mobileapp/core/utils/pending_action_queue.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/client_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/customer_location_result.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/customer_region_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/sync/delegate_sync_engine.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/customer_location/customer_location_controller.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/customer_location/customer_location_page.dart';

/// Scripted GPS: each entry is (delay since listen, accuracy in metres).
class _FakeLocation implements LocationService {
  bool enabled = true;
  LocationPermissionState checkResult = LocationPermissionState.granted;
  LocationPermissionState requestResult = LocationPermissionState.granted;
  List<(Duration, double)> script = [(Duration.zero, 12)];
  int checks = 0, requests = 0, listens = 0, cancels = 0;
  bool openedLocationSettings = false, openedAppSettings = false;

  @override
  Future<bool> isServiceEnabled() async => enabled;
  @override
  Future<LocationPermissionState> checkPermission() async {
    checks++;
    return checkResult;
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    requests++;
    return requestResult;
  }

  @override
  Stream<LocationFix> fixes() {
    late StreamController<LocationFix> c;
    final timers = <Timer>[];
    c = StreamController<LocationFix>(
      onListen: () {
        listens++;
        for (final (delay, acc) in script) {
          timers.add(Timer(delay, () {
            if (!c.isClosed) {
              c.add(LocationFix(latitude: 30.0444, longitude: 31.2357, accuracyM: acc, capturedAt: DateTime.now()));
            }
          }));
        }
      },
      onCancel: () {
        cancels++;
        for (final t in timers) {
          t.cancel();
        }
      },
    );
    return c.stream;
  }

  @override
  Future<bool> openLocationSettings() async => openedLocationSettings = true;
  @override
  Future<bool> openAppSettings() async => openedAppSettings = true;
}

const _fast = CapturePolicy(
  firstFixTimeout: Duration(milliseconds: 300),
  refineWindow: Duration(milliseconds: 200),
);

const _client = ClientModel(id: 7, name: 'بقالة النور', phone: '0100', balance: 0, regionName: 'المعادي');
final _located = ClientModel(
    id: 8, name: 'ماركت السلام', phone: '0111', balance: 0, hasLocation: true, locationRecordedAt: DateTime(2026, 10, 1, 9, 30));

DioException _http(int? status, [String? message]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: {'message': message}),
    );

class _Harness {
  final loc = _FakeLocation();
  final sent = <(int, LocationFix)>[];
  final queued = <PendingAction>[];
  bool online = true;
  Object? sendError;
  bool applied = true;

  late final CustomerLocationController ctrl = CustomerLocationController(
    location: loc,
    policy: _fast,
    isOnline: () => online,
    enqueue: (a) async => queued.add(a),
    send: (id, fix) async {
      if (sendError != null) throw sendError!;
      sent.add((id, fix));
      return CustomerLocationResult(applied: applied, customerId: id, hasLocation: true, locationRecordedAt: fix.capturedAt);
    },
  );

  Future<void> capture(ClientModel c, {bool confirm = true, List<DateTime?>? asked}) => ctrl.capture(c, confirmReplace: (prev) async {
        asked?.add(prev);
        return confirm;
      });
}

void main() {
  group('captureBestFix timing policy', () {
    test('a first fix ≤ 30 m is used at once', () async {
      final loc = _FakeLocation()..script = [(Duration.zero, 18), (const Duration(milliseconds: 50), 5)];
      final fix = await captureBestFix(loc, policy: _fast);
      expect(fix.accuracyM, 18);
      expect(loc.cancels, 1);
    });

    test('a first fix between 30 and 75 m is used at once (no refining)', () async {
      final loc = _FakeLocation()..script = [(Duration.zero, 60), (const Duration(milliseconds: 50), 10)];
      expect((await captureBestFix(loc, policy: _fast)).accuracyM, 60);
    });

    test('a first fix worse than 75 m refines and keeps the best', () async {
      final loc = _FakeLocation()
        ..script = [
          (Duration.zero, 140),
          (const Duration(milliseconds: 40), 90),
          (const Duration(milliseconds: 80), 45),
          (const Duration(milliseconds: 120), 70),
        ];
      final sw = Stopwatch()..start();
      final fix = await captureBestFix(loc, policy: _fast);
      expect(fix.accuracyM, 45);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(190)); // waited out the refine window
      expect(loc.cancels, 1);
    });

    test('refining stops early as soon as a fix ≤ 30 m arrives', () async {
      final loc = _FakeLocation()..script = [(Duration.zero, 200), (const Duration(milliseconds: 30), 25)];
      final sw = Stopwatch()..start();
      expect((await captureBestFix(loc, policy: _fast)).accuracyM, 25);
      expect(sw.elapsedMilliseconds, lessThan(150));
    });

    test('no fix within the first-fix timeout → LocationTimeoutException', () async {
      final loc = _FakeLocation()..script = [];
      await expectLater(captureBestFix(loc, policy: _fast), throwsA(isA<LocationTimeoutException>()));
      expect(loc.cancels, 1);
    });

    test('defaults match the spec: 12 s first fix, 8 s refine, 75/30/100 m', () {
      const p = CapturePolicy();
      expect(p.firstFixTimeout, const Duration(seconds: 12));
      expect(p.refineWindow, const Duration(seconds: 8));
      expect([p.refineAboveM, p.goodEnoughM, p.weakAboveM], [75, 30, 100]);
    });
  });

  group('CustomerLocationController', () {
    test('success: permission ok → capture → send', () async {
      final h = _Harness();
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.success);
      expect(h.sent.single.$1, 7);
      expect(h.sent.single.$2.accuracyM, 12);
      expect(h.queued, isEmpty);
    });

    test('low accuracy: weak state, then retry or save anyway', () async {
      final h = _Harness();
      h.loc.script = [(Duration.zero, 180), (const Duration(milliseconds: 50), 130)];
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.weakAccuracy);
      expect(h.ctrl.fix!.accuracyM, 130);
      expect(h.sent, isEmpty);

      await h.ctrl.saveAnyway(_client);
      expect(h.ctrl.status, CaptureStatus.success);
      expect(h.sent.single.$2.accuracyM, 130);

      h.loc.script = [(Duration.zero, 9)];
      await h.capture(_client);
      expect(h.sent.last.$2.accuracyM, 9);
    });

    test('permission denied, then granted on request', () async {
      final h = _Harness();
      h.loc
        ..checkResult = LocationPermissionState.denied
        ..requestResult = LocationPermissionState.denied;
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.permissionDenied);
      expect(h.loc.requests, 1);
      expect(h.loc.listens, 0);

      h.loc.requestResult = LocationPermissionState.granted;
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.success);
    });

    test('permanently denied → open-settings state, never prompts', () async {
      final h = _Harness();
      h.loc.checkResult = LocationPermissionState.deniedForever;
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.permissionDeniedForever);
      expect(h.loc.requests, 0);
    });

    test('location services off', () async {
      final h = _Harness();
      h.loc.enabled = false;
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.servicesOff);
      expect(h.loc.checks, 0);
    });

    test('timeout', () async {
      final h = _Harness();
      h.loc.script = [];
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.timeout);
      expect(h.sent, isEmpty);
    });

    test('replacing an existing pin asks first, showing the previous date', () async {
      final h = _Harness();
      final asked = <DateTime?>[];
      await h.capture(_located, confirm: false, asked: asked);
      expect(asked, [DateTime(2026, 10, 1, 9, 30)]);
      expect(h.loc.checks, 0);
      expect(h.ctrl.status, CaptureStatus.idle);

      await h.capture(_located, confirm: true);
      expect(h.ctrl.status, CaptureStatus.success);

      // A customer without a pin is never asked.
      asked.clear();
      await h.capture(_client, asked: asked);
      expect(asked, isEmpty);
    });

    test('server kept a newer pin → notApplied', () async {
      final h = _Harness()..applied = false;
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.notApplied);
    });

    test('server rejection (422) shows its message', () async {
      final h = _Harness()..sendError = _http(422, 'إحداثيات غير صالحة (0,0).');
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.error);
      expect(h.ctrl.message, 'إحداثيات غير صالحة (0,0).');
      expect(h.queued, isEmpty);
    });

    test('network failure while "online" keeps the fix in the offline queue', () async {
      final h = _Harness()..sendError = _http(null);
      await h.capture(_client);
      expect(h.ctrl.status, CaptureStatus.savedOffline);
      expect(h.queued.single.type, PendingActionType.customerLocation);
    });
  });

  group('offline queue', () {
    late PendingActionQueue queue;
    late _SyncRepo repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      queue = PendingActionQueue(OfflineCacheService(await SharedPreferences.getInstance()));
      repo = _SyncRepo();
    });

    test('offline capture is queued with captured_at, then replayed once', () async {
      final h = _Harness()..online = false;
      final ctrl = CustomerLocationController(
        location: h.loc,
        policy: _fast,
        isOnline: () => false,
        enqueue: queue.enqueue,
        send: (_, __) => throw StateError('must not send while offline'),
      );
      final before = DateTime.now();
      await ctrl.capture(_client, confirmReplace: (_) async => true);
      expect(ctrl.status, CaptureStatus.savedOffline);

      final action = queue.getAll().single;
      expect(action.type, PendingActionType.customerLocation);
      expect(action.payload['customer_id'], 7);
      expect(action.payload['customer_name'], 'بقالة النور');
      expect(action.payload['accuracy_m'], 12);
      final captured = DateTime.parse(action.payload['captured_at'] as String);
      expect(captured.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);

      // Survives a JSON round trip (app restart) and replays.
      final engine = DelegateSyncEngine(queue, repo, ConnectivityService());
      await engine.syncNow();
      expect(repo.calls.single.customerId, 7);
      expect(repo.calls.single.capturedAt, captured); // the capture time, not the sync time
      expect(queue.getAll().single.status, PendingActionStatus.synced);

      await engine.syncNow(); // nothing left to send
      expect(repo.calls, hasLength(1));
    });

    test('a stale replay (server applied=false) still counts as synced; transient errors retry', () async {
      await queue.enqueue(PendingAction(
        idempotencyKey: 'k1',
        type: PendingActionType.customerLocation,
        payload: {'customer_id': 3, 'customer_name': 'x', 'latitude': 30.1, 'longitude': 31.1, 'accuracy_m': 8.0,
          'captured_at': '2026-10-25T08:00:00.000Z'},
        createdAt: DateTime.now(),
      ));
      final engine = DelegateSyncEngine(queue, repo, ConnectivityService());

      repo.next = _http(null);
      await engine.syncNow();
      expect(queue.getAll().single.status, PendingActionStatus.pending);

      repo.next = null;
      repo.applied = false;
      await engine.syncNow();
      expect(queue.getAll().single.status, PendingActionStatus.synced);
      expect(repo.calls, hasLength(2));
    });

    test('customer deleted meanwhile (404) does not stall the queue', () async {
      await queue.enqueue(PendingAction(
        idempotencyKey: 'k2',
        type: PendingActionType.customerLocation,
        payload: {'customer_id': 99, 'customer_name': 'x', 'latitude': 30.1, 'longitude': 31.1,
          'captured_at': '2026-10-25T08:00:00.000Z'},
        createdAt: DateTime.now(),
      ));
      repo.next = _http(404);
      await DelegateSyncEngine(queue, repo, ConnectivityService()).syncNow();
      expect(queue.getAll().single.status, PendingActionStatus.synced);
    });
  });

  testWidgets('new customer → capture panel right away → capture → ready for the next one', (tester) async {
    final repo = _PageRepo();
    final bloc = DelegateBloc(repo, GpsService());
    final h = _Harness();
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: BlocProvider.value(value: bloc, child: CustomerLocationPage(controller: h.ctrl)),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ عميل جديد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'اسم العميل *'), 'كشك الهدى');
    await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف *'), '01234567890');
    await tester.tap(find.text('حفظ العميل'));
    await tester.pumpAndSettle();

    // Panel for the brand-new customer, no search needed.
    expect(find.text('كشك الهدى'), findsWidgets);
    expect(find.text('الموقع غير مسجل'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('capture-location-button')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(h.sent.single.$1, 501);
    expect(find.textContaining('تم تسجيل الموقع'), findsOneWidget);
    expect(find.text('الموقع غير مسجل'), findsNothing); // panel cleared for the next customer
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 6)); // let the snackbar go
  });

  testWidgets('permanently denied shows the open-settings button', (tester) async {
    final repo = _PageRepo()..clients = [_client];
    final bloc = DelegateBloc(repo, GpsService());
    final h = _Harness();
    h.loc.checkResult = LocationPermissionState.deniedForever;
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(value: bloc, child: CustomerLocationPage(controller: h.ctrl)),
    ));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.location_on), findsNothing); // no pin yet → no marker
    await tester.tap(find.text('بقالة النور'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('capture-location-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('مرفوض نهائيًا'), findsOneWidget);
    await tester.tap(find.text('فتح الإعدادات'));
    expect(h.loc.openedAppSettings, isTrue);
  });
}

class _LocCall {
  final int customerId;
  final DateTime capturedAt;
  _LocCall(this.customerId, this.capturedAt);
}

class _SyncRepo implements DelegateRepository {
  final calls = <_LocCall>[];
  DioException? next;
  bool applied = true;

  @override
  Future<CustomerLocationResult> submitCustomerLocation({
    required int customerId,
    required double latitude,
    required double longitude,
    double? accuracyM,
    required DateTime capturedAt,
  }) async {
    calls.add(_LocCall(customerId, capturedAt));
    if (next != null) throw next!;
    return CustomerLocationResult(applied: applied, customerId: customerId, hasLocation: true);
  }

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _PageRepo implements DelegateRepository {
  List<ClientModel> clients = [];

  @override
  Future<List<ClientModel>> searchClients(String query) async => clients;
  @override
  List<ClientModel> getCachedCustomerList() => clients;
  @override
  Future<List<CustomerRegionModel>> getCustomerRegions() async => [];
  @override
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    int? customerRegionId,
    double? initialBalance,
  }) async =>
      ClientModel(id: 501, name: name, phone: phone, balance: 0);

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}
