import 'package:alkhair_mobileapp/core/di/service_locator.dart';
import 'package:alkhair_mobileapp/core/utils/connectivity_service.dart';
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/offline_cache_service.dart';
import 'package:alkhair_mobileapp/core/utils/pending_action_queue.dart';
import 'package:alkhair_mobileapp/core/utils/push_notification_service.dart';
import 'package:alkhair_mobileapp/features/app_config/domain/repositories/app_config_repository.dart';
import 'package:alkhair_mobileapp/features/app_config/presentation/bloc/app_config_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';
import 'package:alkhair_mobileapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:alkhair_mobileapp/features/auth/domain/usecases/login_usecase.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_event.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/invoice_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/loading_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/sellable_product_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/sync_state_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/sync/delegate_sync_engine.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/transaction_record_models.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/settlement_summary_model.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_event.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_home_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/invoice_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/sync/delegate_sync_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Part 1.5 — the delegate's loading / stock / settlement state is one
/// shared, self-updating source of truth (DelegateSyncService). These drive
/// the REAL DelegateHomePage against a scripted in-memory "server".

// ── Scripted server ─────────────────────────────────────────────────────────

class _Server {
  LoadingModel? loading;
  int loadingVersion = 0;
  final Map<int, double> stock = {};
  int stockVersion = 0;
  SyncSettlementRef? settlement;
  bool offline = false;
  int syncCalls = 0;

  static const productId = 7;

  LoadingModel _loadingWith(String status) => LoadingModel(
        id: 42,
        delegateId: 1,
        warehouseId: 3,
        warehouseName: 'المستودع الرئيسي',
        status: status,
        items: [
          LoadingItemModel.fromJson({
            'id': 1, 'product_id': productId, 'quantity_requested': 10, 'quantity_confirmed': 0,
            'product': {'id': productId, 'name': 'جبن', 'unit': 'kg'},
          }),
        ],
      );

  void assignLoading() {
    loading = _loadingWith('pending_pickup');
    loadingVersion++;
  }

  void setStatus(String status) {
    loading = _loadingWith(status);
    loadingVersion++;
  }

  void setStock(double qty) {
    stock[productId] = qty;
    stockVersion++;
  }

  SyncStateModel state() => SyncStateModel(
        loading: loading == null
            ? null
            : SyncLoadingRef(id: loading!.id, status: loading!.status, updatedAt: 'v$loadingVersion'),
        pendingAdditionIds: const [],
        settlementRequest: settlement,
        stockVersion: 's$stockVersion',
      );

  String etag() => '"${loading?.status}-$loadingVersion-$stockVersion-${settlement?.status}"';

  void throwIfOffline() {
    if (offline) {
      throw DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionError);
    }
  }
}

class _Repo implements DelegateRepository {
  final _Server server;
  final LoadingModel? cachedLoading;
  _Repo(this.server, {this.cachedLoading});

  @override
  Future<SyncStateResult> getSyncState({String? etag}) async {
    server.syncCalls++;
    server.throwIfOffline();
    final tag = server.etag();
    if (tag == etag) return SyncStateResult.notModified(tag);
    return SyncStateResult.fresh(server.state(), tag);
  }

  @override
  Future<LoadingModel?> getCurrentLoading() async {
    server.throwIfOffline();
    return server.loading;
  }

  @override
  Future<List<TruckStockModel>> getTruckStock() async {
    server.throwIfOffline();
    return [
      for (final e in server.stock.entries)
        TruckStockModel(id: e.key, productId: e.key, productName: 'جبن', productUnit: 'kg', currentStockQty: e.value),
    ];
  }

  @override
  Future<List<SellableProductModel>> getSellableProducts({int? customerId}) async => const [];

  @override
  Future<LoadingModel> confirmLoading() async {
    server.throwIfOffline();
    server.setStatus('accepted');
    server.setStock(10);
    return server.loading!;
  }

  @override
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double discountAmount = 0,
    double? latitude,
    double? longitude,
    String? idempotencyKey,
  }) async {
    for (final s in salesItems) {
      final id = s['product_id'] as int;
      server.stock[id] = (server.stock[id] ?? 0) - (s['qty'] as num).toDouble();
    }
    server.stockVersion++;
    return DelegateInvoiceModel.fromJson({'id': 900, 'customer_id': clientId, 'created_at': '2026-10-10T10:00:00Z'});
  }

  @override
  LoadingModel? getCachedLoading() => cachedLoading;
  @override
  List<TruckStockModel> getCachedTruckStock() => const [];
  @override
  List<SellableProductModel> getCachedSellableProducts() => const [];
  @override
  Future<List<DelegateInvoiceModel>> getInvoices() async => const [];
  @override
  Future<List<ExpenseRecordModel>> getExpenseRecords() async => const [];
  @override
  Future<List<CustomerCollectionRecordModel>> getCustomerCollectionRecords() async => const [];
  @override
  Future<SettlementSummaryModel> getSettlementSummary() async => throw DioException(
        requestOptions: RequestOptions(path: '/delegate/shift-summary'),
        response: Response(requestOptions: RequestOptions(path: '/'), statusCode: 404),
        type: DioExceptionType.badResponse,
      );

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

// ── Harness ────────────────────────────────────────────────────────────────

class _FakeGps implements GpsService {
  @override
  Future<({double? lat, double? lng})> captureCoordinates() async => (lat: null, lng: null);
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakePush implements PushNotificationService {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeLogin implements LoginUseCase {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeAuthRepo implements AuthRepository {
  @override
  Future<UserModel?> restoreSession() async => const UserModel(
        id: 1, name: 'مندوب', email: 'd@test.local', role: 'delegate', isActive: true,
        permissions: [], hasActiveLoading: false, truckStockCount: 0,
        // No payroll dashboard (and so no dashboard fetch) for this rep type
        // — keeps these tests about the shipment/stock state only.
        isFreePricingDelegate: true,
      );
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeAppConfigRepo implements AppConfigRepository {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

const _interval = Duration(seconds: 8);

Future<({DelegateSyncService sync, DelegateBloc bloc})> _pumpHome(
  WidgetTester tester,
  _Server server, {
  LoadingModel? cachedLoading,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await sl.reset();
  final queue = PendingActionQueue(OfflineCacheService(prefs));
  final connectivity = ConnectivityService();
  sl.registerSingleton<PendingActionQueue>(queue);
  sl.registerSingleton<ConnectivityService>(connectivity);

  final repo = _Repo(server, cachedLoading: cachedLoading);
  // Real engine, empty queue: the home page asks it to replay on resume.
  sl.registerSingleton<DelegateSyncEngine>(DelegateSyncEngine(queue, repo, connectivity));
  final auth = AuthBloc(_FakeLogin(), _FakeAuthRepo(), _FakePush())..add(AuthSessionRestoreRequested());
  await auth.stream.firstWhere((s) => s.runtimeType.toString() == 'AuthAuthenticated');
  final bloc = DelegateBloc(repo, _FakeGps());
  final appConfig = AppConfigBloc(_FakeAppConfigRepo());
  final sync = DelegateSyncService(repo, interval: _interval);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    sync.dispose();
    await bloc.close();
    await auth.close();
    await appConfig.close();
    await sl.reset();
  });

  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<AuthBloc>.value(value: auth),
      BlocProvider<DelegateBloc>.value(value: bloc),
      BlocProvider<AppConfigBloc>.value(value: appConfig),
    ],
    child: DelegateSyncScope(service: sync, child: const MaterialApp(home: DelegateHomePage())),
  ));
  return (sync: sync, bloc: bloc);
}

/// Lets in-flight fakes resolve without advancing a poll interval.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _sellTab => find.text('البيع');
Finder get _noShipment => find.text('لا توجد شحنة');

void main() {
  testWidgets('before the first successful sync the card is a skeleton — never "no shipment"', (tester) async {
    final server = _Server();
    await _pumpHome(tester, server);
    // First frame: nothing known yet (no cache, sync in flight).
    expect(find.byKey(const Key('shipment-skeleton')), findsOneWidget);
    expect(_noShipment, findsNothing);
    await _settle(tester);
    // Only now — after the server said so — "no shipment".
    expect(_noShipment, findsOneWidget);
  });

  testWidgets('a loading assigned by the admin while the delegate sits on home appears within one poll interval',
      (tester) async {
    final server = _Server();
    await _pumpHome(tester, server);
    await _settle(tester);
    expect(_noShipment, findsOneWidget);

    server.assignLoading(); // admin creates it on the server
    await tester.pump(_interval);
    await _settle(tester);

    expect(_noShipment, findsNothing);
    expect(find.text('عندك شحنة جديدة بانتظار الاستلام'), findsOneWidget);
    expect(find.text('مراجعة وتأكيد الاستلام'), findsOneWidget);
  });

  testWidgets('after confirm-pickup the sell tab is usable immediately, without waiting for a poll', (tester) async {
    final server = _Server()..assignLoading();
    await _pumpHome(tester, server);
    await _settle(tester);
    expect(find.text('عندك شحنة جديدة بانتظار الاستلام'), findsOneWidget);

    // Review & confirm from the home notice (LoadingPage's real flow).
    await tester.tap(find.text('مراجعة وتأكيد الاستلام'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'تأكيد الاستلام'));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1)); // route transition
    // LoadingPage replaced itself with the sell screen; go back home.
    expect(find.byType(InvoicePage), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));

    final callsBefore = server.syncCalls;
    await tester.tap(_sellTab);
    await tester.pump();
    // The tab switched — no "لا توجد تحميلة نشطة" snackbar, no poll needed.
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    for (final gate in ['لا توجد شحنة نشطة', 'بانتظار الاستلام', 'جاري التحقق']) {
      expect(find.descendant(of: find.byType(SnackBar), matching: find.textContaining(gate)), findsNothing);
    }
    expect(server.syncCalls - callsBefore, lessThanOrEqualTo(1), reason: 'only the tab-visible trigger');
  });

  testWidgets('the عمليات tab leaves the "no active loading" banner by itself', (tester) async {
    final server = _Server();
    await _pumpHome(tester, server);
    await _settle(tester);
    await tester.tap(find.text('عمليات'));
    await _settle(tester);
    const banner = 'لا توجد تحميلة نشطة حالياً — لا يمكن تسجيل مصروف أو تحصيل الآن.';
    expect(find.text(banner), findsOneWidget);

    server
      ..assignLoading()
      ..setStatus('accepted')
      ..setStock(10);
    await tester.pump(_interval);
    await _settle(tester);

    expect(find.text(banner), findsNothing);
  });

  testWidgets('a failed / offline sync never flips the state to "none"', (tester) async {
    final server = _Server()..setStatus('accepted');
    final h = await _pumpHome(tester, server);
    await _settle(tester);
    expect(find.text('مستلمة'), findsOneWidget);

    server.offline = true;
    for (var i = 0; i < 3; i++) {
      await tester.pump(_interval);
      await _settle(tester);
    }
    expect(h.sync.lastSyncFailed, isTrue);
    expect(_noShipment, findsNothing);
    expect(find.text('مستلمة'), findsOneWidget, reason: 'last known shipment stays on screen');
    expect(h.sync.lifecycle, DelegateLifecycle.accepted);
  });

  testWidgets('offline from the very start: an error with retry, never "no shipment"', (tester) async {
    final server = _Server()..offline = true;
    await _pumpHome(tester, server);
    await _settle(tester);
    expect(_noShipment, findsNothing);
    expect(find.text('تعذر تحميل حالة الشحنة'), findsOneWidget);

    server
      ..offline = false
      ..assignLoading();
    await tester.tap(find.text('إعادة المحاولة'));
    await _settle(tester);
    expect(find.text('عندك شحنة جديدة بانتظار الاستلام'), findsOneWidget);
  });

  testWidgets('a stale cached snapshot never overrides the server: cached pending vs server active', (tester) async {
    final server = _Server()..setStatus('accepted');
    final stale = (_Server()..assignLoading()).loading!; // cached "pending_pickup"
    // The cache seeds the state before the first sync — marked stale...
    final seeded = DelegateSyncService(_Repo(server, cachedLoading: stale));
    expect(seeded.lifecycle, DelegateLifecycle.pendingPickup);
    expect(seeded.isShowingStaleData, isTrue);
    seeded.dispose();
    final h = await _pumpHome(tester, server, cachedLoading: stale);
    await _settle(tester);
    // ...and the server answer replaces it.
    expect(h.sync.lifecycle, DelegateLifecycle.accepted);
    expect(find.text('عندك شحنة جديدة بانتظار الاستلام'), findsNothing);

    // A later failure + a cache that says nothing ("none") changes nothing.
    server.offline = true;
    await tester.pump(_interval);
    await _settle(tester);
    expect(h.sync.lifecycle, DelegateLifecycle.accepted);
    expect(_noShipment, findsNothing);
  });

  testWidgets('truck stock changes after a sale appear without a manual reload', (tester) async {
    final server = _Server()
      ..setStatus('accepted')
      ..setStock(10);
    final h = await _pumpHome(tester, server);
    await _settle(tester);
    await tester.tap(find.text('المخزون'));
    await _settle(tester);
    expect(find.text('10.00'), findsOneWidget);

    // A sale submitted through the shared bloc (as the sell tab does).
    h.bloc.add(DelegateInvoiceSubmitted(
      clientId: 5,
      salesItems: [InvoiceSaleItem(productId: _Server.productId, productName: 'جبن', quantity: 2, unitPrice: 100)],
      returnedItems: const [],
      cashReceived: 200,
    ));
    await _settle(tester); // well under one poll interval

    expect(find.text('8.00'), findsOneWidget);
    expect(find.text('10.00'), findsNothing);
  });

  testWidgets('unchanged state costs a 304, and polling pauses in the background', (tester) async {
    final server = _Server()..setStatus('accepted');
    final h = await _pumpHome(tester, server);
    await _settle(tester);
    final revision = h.sync.revision;

    await tester.pump(_interval);
    await _settle(tester);
    expect(h.sync.revision, revision, reason: '304 → nothing re-applied');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final calls = server.syncCalls;
    await tester.pump(_interval * 4);
    expect(server.syncCalls, calls, reason: 'no polling while backgrounded');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(server.syncCalls, calls + 1, reason: 'resume syncs immediately');
  });

  testWidgets('after a settlement request it polls fast until the admin confirms, then shows "settled"',
      (tester) async {
    final server = _Server()..setStatus('in_transit');
    final h = await _pumpHome(tester, server);
    await _settle(tester);

    server.settlement = const SyncSettlementRef(id: 1, loadingId: 42, status: 'pending');
    h.sync.accelerate();
    await h.sync.refreshNow();
    await _settle(tester);
    expect(h.sync.lifecycle, DelegateLifecycle.settlementRequested);
    expect(find.text('بانتظار تأكيد التسليم من الإدارة'), findsOneWidget);
    expect(h.sync.currentInterval, h.sync.fastInterval);

    // Admin confirms: loading leaves the active set.
    server.loading = null;
    server.loadingVersion++;
    server.settlement = const SyncSettlementRef(id: 1, loadingId: 42, status: 'confirmed');
    await tester.pump(h.sync.fastInterval); // fast cadence, well under 8s
    await _settle(tester);
    expect(h.sync.lifecycle, DelegateLifecycle.settled);
    expect(find.text('تمت تسوية الشحنة'), findsOneWidget);
    expect(h.sync.currentInterval, _interval, reason: 'back to normal once nothing is pending');
  });
}
