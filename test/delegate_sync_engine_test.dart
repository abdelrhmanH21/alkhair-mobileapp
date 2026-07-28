import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alkhair_mobileapp/core/utils/connectivity_service.dart';
import 'package:alkhair_mobileapp/core/utils/offline_cache_service.dart';
import 'package:alkhair_mobileapp/core/utils/pending_action_queue.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/invoice_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/loading_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/sellable_product_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/sync/delegate_sync_engine.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';

/// Records every submitInvoice/submitExpense/submitCustomerCollection call
/// (in call order — the whole point of these tests) and lets each call be
/// scripted to either succeed or throw a specific DioException, by
/// idempotency key. Every other DelegateRepository method throws if called —
/// none of them are exercised by DelegateSyncEngine except the two
/// post-sale-sync cache refreshes, which are stubbed to no-ops below.
class _FakeDelegateRepository implements DelegateRepository {
  final List<String> callOrder = [];
  final Map<String, DioException> scriptedResults = {}; // idempotencyKey -> thrown on submit; absent = success

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
    callOrder.add(idempotencyKey!);
    final scripted = scriptedResults[idempotencyKey];
    if (scripted != null) throw scripted;
    return DelegateInvoiceModel.fromJson({
      'id': 1,
      'invoice_number': 'DINV-000001',
      'delegate_id': 1,
      'customer_id': clientId,
      'loading_id': 1,
      'gross_sales_total': cashReceived,
      'discount_amount': discountAmount,
      'total_returns': 0,
      'net_total': cashReceived,
      'cash_received': cashReceived,
      'balance_added_to_debt': 0,
      'debt_reduction': 0,
      'prior_debt': 0,
      'status': 'confirmed',
      'items': [],
      'returns': [],
    });
  }

  @override
  Future<String> submitExpense({
    required double amount,
    required String description,
    int? categoryId,
    String? notes,
    String? idempotencyKey,
  }) async {
    callOrder.add(idempotencyKey!);
    final scripted = scriptedResults[idempotencyKey];
    if (scripted != null) throw scripted;
    return 'تم تسجيل المصروف بنجاح.';
  }

  @override
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
    String? idempotencyKey,
  }) async {
    callOrder.add(idempotencyKey!);
    final scripted = scriptedResults[idempotencyKey];
    if (scripted != null) throw scripted;
    return 'تم تسجيل التحصيل بنجاح.';
  }

  @override
  Future<List<TruckStockModel>> getTruckStock() async => [];

  @override
  Future<List<SellableProductModel>> getSellableProducts({int? customerId}) async => [];

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('DelegateRepository.${invocation.memberName} not used by this test');
}

DioException _networkError() => DioException(
      requestOptions: RequestOptions(path: '/v1/mobile/delegate/invoice'),
      type: DioExceptionType.connectionError,
    );

DioException _businessRejection(String message) => DioException(
      requestOptions: RequestOptions(path: '/v1/mobile/delegate/invoice'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/v1/mobile/delegate/invoice'),
        statusCode: 422,
        data: {'message': message},
      ),
    );

void main() {
  late _FakeDelegateRepository repo;
  late PendingActionQueue queue;
  late DelegateSyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = OfflineCacheService(prefs);
    queue = PendingActionQueue(cache);
    repo = _FakeDelegateRepository();
    // Default (no initialize() call) ConnectivityService reports isOnline
    // == true — exactly what these tests need; none of them exercise the
    // "device is actually offline" branch of syncNow() itself.
    engine = DelegateSyncEngine(queue, repo, ConnectivityService());
  });

  PendingAction saleAction(String key, DateTime createdAt) => PendingAction(
        idempotencyKey: key,
        type: PendingActionType.sale,
        payload: const {
          'client_id': 1,
          'client_name': 'Test',
          'sales_items': [
            {'product_id': 1, 'product_name': 'P', 'qty': 1, 'unit_price': 10},
          ],
          'returned_items': [],
          'cash_received': 10,
          'discount_amount': 0,
          'latitude': null,
          'longitude': null,
        },
        createdAt: createdAt,
      );

  test('processes queued actions in strict FIFO (creation) order, not enqueue-call order', () async {
    final now = DateTime.now();
    // Enqueue out of chronological order — getAll() must still return (and
    // the engine must still process) oldest-createdAt-first.
    await queue.enqueue(saleAction('key-2', now.add(const Duration(seconds: 2))));
    await queue.enqueue(saleAction('key-1', now));
    await queue.enqueue(saleAction('key-3', now.add(const Duration(seconds: 3))));

    await engine.syncNow();

    expect(repo.callOrder, ['key-1', 'key-2', 'key-3']);
  });

  test('a retried sync reuses the exact same idempotency key, never a new one', () async {
    const key = 'retry-key';
    await queue.enqueue(saleAction(key, DateTime.now()));

    // First attempt: network failure — must leave the action pending (not
    // failed, not removed) so a later trigger retries it.
    repo.scriptedResults[key] = _networkError();
    await engine.syncNow();

    final afterFirstAttempt = queue.getAll().single;
    expect(afterFirstAttempt.status, PendingActionStatus.pending);
    expect(afterFirstAttempt.idempotencyKey, key);
    expect(repo.callOrder, [key]);

    // Second attempt (e.g. connectivity restored) succeeds — clearing the
    // scripted failure means the fake's default (success) path runs.
    repo.scriptedResults.remove(key);
    await engine.syncNow();

    expect(repo.callOrder, [key, key], reason: 'same key used both times');
    final afterSecondAttempt = queue.getAll().single;
    expect(afterSecondAttempt.status, PendingActionStatus.synced);
  });

  test('a network-type failure stops the whole pass, preserving order for dependent later actions', () async {
    await queue.enqueue(saleAction('key-1', DateTime.now()));
    await queue.enqueue(saleAction('key-2', DateTime.now().add(const Duration(seconds: 1))));
    repo.scriptedResults['key-1'] = _networkError();

    await engine.syncNow();

    // key-2 must never have been attempted — key-1 might depend on nothing,
    // but the engine can't know that in general, and must not risk running
    // key-2 "out of order" while key-1's true server-side outcome is
    // unknown.
    expect(repo.callOrder, ['key-1']);
    final all = {for (final a in queue.getAll()) a.idempotencyKey: a.status};
    expect(all['key-1'], PendingActionStatus.pending);
    expect(all['key-2'], PendingActionStatus.pending);
  });

  test('oversell-rejection (422) marks that action failed with the reason, then continues to the next action', () async {
    await queue.enqueue(saleAction('key-1', DateTime.now()));
    await queue.enqueue(saleAction('key-2', DateTime.now().add(const Duration(seconds: 1))));
    repo.scriptedResults['key-2'] = _businessRejection(
      'رصيد الشاحنة غير كافٍ للمنتج: تست. المتاح: 2',
    );

    await engine.syncNow();

    expect(repo.callOrder, ['key-1', 'key-2'], reason: 'a business rejection does not block later actions');
    final byKey = {for (final a in queue.getAll()) a.idempotencyKey: a};
    expect(byKey['key-1']!.status, PendingActionStatus.synced);
    expect(byKey['key-2']!.status, PendingActionStatus.failed);
    expect(byKey['key-2']!.failureReason, contains('رصيد الشاحنة غير كافٍ'));
  });

  test('overlapping syncNow() calls never run concurrently', () async {
    await queue.enqueue(saleAction('key-1', DateTime.now()));
    await queue.enqueue(saleAction('key-2', DateTime.now().add(const Duration(seconds: 1))));

    // Fire two passes back-to-back without awaiting the first — the second
    // must be a no-op (guarded by _syncing) rather than double-processing.
    final first = engine.syncNow();
    final second = engine.syncNow();
    await Future.wait([first, second]);

    expect(repo.callOrder, ['key-1', 'key-2'], reason: 'each action submitted exactly once total');
  });
}
