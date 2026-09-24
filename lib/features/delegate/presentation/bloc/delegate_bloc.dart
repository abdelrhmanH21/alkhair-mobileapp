import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../domain/repositories/delegate_repository.dart';
import '../../data/models/loading_model.dart';
import '../../data/models/client_model.dart';
import '../../data/models/dashboard_model.dart';
import '../../data/models/sellable_product_model.dart';
import '../../../../core/utils/gps_service.dart';
import 'delegate_event.dart';
import 'delegate_state.dart';

class DelegateBloc extends Bloc<DelegateEvent, DelegateState> {
  final DelegateRepository _repo;
  final GpsService _gps;

  // ── Offline cache reads (synchronous passthroughs) ───────────────────────
  // Screens read these via context.read<DelegateBloc>() — the bloc's own
  // injected repository instance — rather than reaching into the global
  // service-locator singleton directly, so tests that construct a
  // DelegateBloc with a fake/in-memory DelegateRepository (never registered
  // with `sl`) keep working unchanged.
  LoadingModel? getCachedLoading() => _repo.getCachedLoading();
  List<TruckStockModel> getCachedTruckStock() => _repo.getCachedTruckStock();
  DashboardModel? getCachedDashboard() => _repo.getCachedDashboard();
  List<SellableProductModel> getCachedSellableProducts() => _repo.getCachedSellableProducts();
  List<ClientModel> getCachedCustomerList() => _repo.getCachedCustomerList();

  /// See DelegateRepository.applyOptimisticTruckStockDelta — used when a
  /// sale is queued offline instead of submitted live.
  Future<void> applyOptimisticTruckStockDelta(Map<int, double> productIdToQtyDelta) =>
      _repo.applyOptimisticTruckStockDelta(productIdToQtyDelta);

  /// Waits between confirm-pickup attempts (its length + 1 = max attempts).
  /// Injectable only so tests don't sleep real seconds.
  final List<Duration> _confirmRetryBackoff;

  DelegateBloc(
    this._repo,
    this._gps, {
    List<Duration> confirmRetryBackoff = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
  })  : _confirmRetryBackoff = confirmRetryBackoff,
        super(const DelegateInitial()) {
    on<DelegateLoadingFetched>(_onFetchLoading);
    on<DelegateLoadingConfirmed>(_onConfirmLoading);
    on<DelegateLoadingAdditionConfirmed>(_onConfirmLoadingAddition);
    on<DelegateTruckStockFetched>(_onFetchTruckStock);
    on<DelegateDashboardRequested>(_onFetchDashboard);
    on<DelegateClientSearchRequested>(_onSearchClients);
    on<DelegateClientCreated>(_onCreateClient);
    on<DelegateInvoiceSubmitted>(_onSubmitInvoice);
    on<DelegateInvoiceUpdateRequested>(_onUpdateInvoice);
    on<DelegateInvoicesFetched>(_onFetchInvoices);
    on<DelegateLoadingStatusUpdateRequested>(_onUpdateLoadingStatus);
    on<DelegateSellableProductsFetched>(_onFetchSellableProducts);
    on<DelegateSalesCatalogFetched>(_onFetchSalesCatalog);
    on<DelegateCustomerRegionsFetched>(_onFetchCustomerRegions);
    on<DelegateSettlementSummaryRequested>(_onFetchSettlementSummary);
    on<DelegateSettlementRequestSubmitted>(_onSubmitSettlementRequest);
    on<DelegatePenaltiesFetched>(_onFetchPenalties);
    on<DelegateAdvancesFetched>(_onFetchAdvances);
    on<DelegateBonusesFetched>(_onFetchBonuses);
    on<DelegateCommissionBreakdownFetched>(_onFetchCommissionBreakdown);
    on<DelegatePriceVarianceSummaryFetched>(_onFetchPriceVarianceSummary);
    on<DelegateExpenseSubmitted>(_onSubmitExpense);
    on<DelegateNoteSubmitted>(_onSubmitNote);
    on<DelegateCustomerCollectionSubmitted>(_onSubmitCustomerCollection);
    on<DelegateExpenseRecordsFetched>(_onFetchExpenseRecords);
    on<DelegateExpenseRecordUpdateRequested>(_onUpdateExpenseRecord);
    on<DelegateExpenseRecordDeleteRequested>(_onDeleteExpenseRecord);
    on<DelegateCustomerCollectionRecordsFetched>(_onFetchCustomerCollectionRecords);
    on<DelegateCustomerCollectionRecordUpdateRequested>(_onUpdateCustomerCollectionRecord);
    on<DelegateCustomerCollectionRecordDeleteRequested>(_onDeleteCustomerCollectionRecord);
    on<DelegateReportByRegionRequested>(_onFetchReportByRegion);
    on<DelegateReportByProductRequested>(_onFetchReportByProduct);
  }

  Future<void> _onFetchLoading(
    DelegateLoadingFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final loading = await _repo.getCurrentLoading();
      emit(DelegateLoadingLoaded(loading, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onConfirmLoading(
    DelegateLoadingConfirmed event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    // Transient failures (timeouts, dropped connections, 5xx from the
    // server/Cloudflare) are retried silently — confirm() is idempotent
    // server-side (a replay after an already-committed confirm returns the
    // accepted loading, never double-deducts), so retrying is always safe.
    // The page stays in its busy state throughout and only ever sees the
    // FINAL outcome: no intermediate error can flash.
    final maxAttempts = _confirmRetryBackoff.length + 1;
    final sw = Stopwatch()..start();
    for (var attempt = 1; ; attempt++) {
      try {
        final loading = await _repo.confirmLoading();
        _logConfirm(event.requestId, 'ok attempt=$attempt/$maxAttempts '
            'status=${loading.status} elapsed=${sw.elapsedMilliseconds}ms');
        emit(DelegateLoadingConfirmedState(loading, requestId: event.requestId));
        return;
      } on DioException catch (e) {
        final transient = _isTransient(e);
        _logConfirm(event.requestId, 'fail attempt=$attempt/$maxAttempts '
            'type=${e.type.name} http=${e.response?.statusCode} '
            'transient=$transient elapsed=${sw.elapsedMilliseconds}ms');
        if (transient && attempt < maxAttempts) {
          await Future<void>.delayed(_confirmRetryBackoff[attempt - 1]);
          continue;
        }
        emit(DelegateFailure(_parseError(e), requestId: event.requestId));
        return;
      } catch (e, st) {
        // Not a network problem — the server answered but the client
        // couldn't handle it (this is how the created_by TypeError hid for
        // months behind a generic message). Never retried; logged in full.
        _logConfirm(event.requestId, 'client error attempt=$attempt '
            'elapsed=${sw.elapsedMilliseconds}ms: $e\n$st');
        emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
        return;
      }
    }
  }

  static bool _isTransient(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        // 4xx are real answers (nothing pending, insufficient stock, 401) —
        // retrying can't change them. 5xx/Cloudflare 52x may be transient.
        return (e.response?.statusCode ?? 0) >= 500;
      default:
        return false;
    }
  }

  /// Permanent, low-noise diagnostics for the confirm-pickup action only
  /// (one line per attempt) — so a future recurrence can be diagnosed from
  /// `adb logcat | grep confirm-pickup` instead of guessed at.
  static void _logConfirm(String requestId, String message) =>
      debugPrint('[confirm-pickup] req=$requestId $message');

  Future<void> _onConfirmLoadingAddition(
    DelegateLoadingAdditionConfirmed event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      await _repo.confirmLoadingAddition(event.additionId);
      // Re-fetch so pendingAdditions/items/truck-stock-backing state all
      // reflect the just-confirmed addition, same as confirmLoading() above
      // returns the loading fresh from the server rather than patching it
      // locally.
      final loading = await _repo.getCurrentLoading();
      emit(DelegateLoadingAdditionConfirmedState(loading, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchTruckStock(
    DelegateTruckStockFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final stocks = await _repo.getTruckStock();
      emit(DelegateTruckStockLoaded(stocks, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchDashboard(
    DelegateDashboardRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final dashboard = await _repo.getDashboard();
      emit(DelegateDashboardLoaded(dashboard, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSearchClients(
    DelegateClientSearchRequested event,
    Emitter<DelegateState> emit,
  ) async {
    try {
      final clients = await _repo.searchClients(event.query);
      emit(DelegateClientSearchResults(clients, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ في البحث. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onCreateClient(
    DelegateClientCreated event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final client = await _repo.createClient(
        name: event.name,
        phone: event.phone,
        region: event.region,
        customerRegionId: event.customerRegionId,
        initialBalance: event.initialBalance,
      );
      emit(DelegateClientCreatedState(client, requestId: event.requestId));
    } on DioException catch (e) {
      final fieldErrors = e.response?.data?['errors'] as Map<String, dynamic>?;
      if (e.response?.statusCode == 422 && fieldErrors != null) {
        emit(DelegateClientValidationFailure(
          fieldErrors.map((k, v) => MapEntry(k, (v as List).map((s) => s.toString()).toList())),
          _parseError(e),
          requestId: event.requestId,
        ));
      } else {
        emit(DelegateFailure(_parseError(e), requestId: event.requestId));
      }
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchSellableProducts(
    DelegateSellableProductsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final products = await _repo.getSellableProducts(customerId: event.customerId);
      emit(DelegateSellableProductsLoaded(products, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchSalesCatalog(
    DelegateSalesCatalogFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final products = await _repo.getSalesCatalogProducts();
      emit(DelegateSalesCatalogLoaded(products, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchCustomerRegions(
    DelegateCustomerRegionsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    try {
      final regions = await _repo.getCustomerRegions();
      emit(DelegateCustomerRegionsLoaded(regions, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSubmitInvoice(
    DelegateInvoiceSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      // GPS capture is fire-and-forget — never blocks the invoice
      final coords = await _gps.captureCoordinates();

      final salesItems = event.salesItems
          .map((s) => {
                'product_id': s.productId,
                'qty': s.quantity,
                'unit_price': s.unitPrice,
              })
          .toList();

      final returnedItems = event.returnedItems
          .map((r) => {
                'product_id': r.productId,
                'qty': r.quantity,
                'unit_price': r.unitPrice,
                'status': r.condition,
                'refund_method': r.refundMethod,
                if (r.replacementProductId != null)
                  'replacement_product_id': r.replacementProductId,
                if (r.replacementQuantity != null)
                  'replacement_quantity': r.replacementQuantity,
                if (r.replacementUnitPrice != null)
                  'replacement_unit_price': r.replacementUnitPrice,
              })
          .toList();

      final invoice = await _repo.submitInvoice(
        clientId: event.clientId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: event.cashReceived,
        discountAmount: event.discountAmount,
        latitude: coords.lat,
        longitude: coords.lng,
      );
      emit(DelegateInvoiceSubmittedState(invoice, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onUpdateInvoice(
    DelegateInvoiceUpdateRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final salesItems = event.salesItems
          .map((s) => {
                'product_id': s.productId,
                'qty': s.quantity,
                'unit_price': s.unitPrice,
              })
          .toList();

      final returnedItems = event.returnedItems
          .map((r) => {
                'product_id': r.productId,
                'qty': r.quantity,
                'unit_price': r.unitPrice,
                'status': r.condition,
                'refund_method': r.refundMethod,
                if (r.replacementProductId != null)
                  'replacement_product_id': r.replacementProductId,
                if (r.replacementQuantity != null)
                  'replacement_quantity': r.replacementQuantity,
                if (r.replacementUnitPrice != null)
                  'replacement_unit_price': r.replacementUnitPrice,
              })
          .toList();

      final invoice = await _repo.updateInvoice(
        invoiceId: event.invoiceId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: event.cashReceived,
        discountAmount: event.discountAmount,
      );
      emit(DelegateInvoiceUpdatedState(invoice, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchInvoices(
    DelegateInvoicesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final invoices = await _repo.getInvoices();
      emit(DelegateInvoicesLoaded(invoices, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onUpdateLoadingStatus(
    DelegateLoadingStatusUpdateRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final loading = await _repo.updateLoadingStatus(event.loadingId, event.status);
      emit(DelegateLoadingStatusUpdated(loading, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchSettlementSummary(
    DelegateSettlementSummaryRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final summary = await _repo.getSettlementSummary();
      emit(DelegateSettlementSummaryLoaded(summary, requestId: event.requestId));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        emit(DelegateNoActiveShift(requestId: event.requestId));
      } else {
        emit(DelegateFailure(_parseError(e), requestId: event.requestId));
      }
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSubmitSettlementRequest(
    DelegateSettlementRequestSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      await _repo.submitSettlementRequest(
        cashAmount: event.cashAmount,
        walletAmount: event.walletAmount,
        notes: event.notes,
      );
      emit(DelegateSettlementRequestSubmittedState(
        'تم إرسال طلب التسليم، بانتظار تأكيد الإدارة.',
        requestId: event.requestId,
      ));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchPenalties(
    DelegatePenaltiesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final penalties = await _repo.getPenalties();
      emit(DelegatePenaltiesLoaded(penalties, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchAdvances(
    DelegateAdvancesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final advances = await _repo.getAdvances();
      emit(DelegateAdvancesLoaded(advances, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchBonuses(
    DelegateBonusesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final bonuses = await _repo.getBonuses();
      emit(DelegateBonusesLoaded(bonuses, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchCommissionBreakdown(
    DelegateCommissionBreakdownFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final days = await _repo.getCommissionBreakdown();
      emit(DelegateCommissionBreakdownLoaded(days, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchPriceVarianceSummary(
    DelegatePriceVarianceSummaryFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final summary = await _repo.getPriceVarianceSummary();
      emit(DelegatePriceVarianceSummaryLoaded(summary, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSubmitExpense(
    DelegateExpenseSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final message = await _repo.submitExpense(
        amount: event.amount,
        description: event.description,
        photo: event.photo,
        categoryId: event.categoryId,
        notes: event.notes,
      );
      emit(DelegateExpenseSubmittedState(message, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSubmitNote(
    DelegateNoteSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final message = await _repo.submitNote(message: event.message, photo: event.photo);
      emit(DelegateNoteSubmittedState(message, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onSubmitCustomerCollection(
    DelegateCustomerCollectionSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final message = await _repo.submitCustomerCollection(
        customerId: event.customerId,
        amount: event.amount,
        paymentMethod: event.paymentMethod,
        notes: event.notes,
      );
      emit(DelegateCustomerCollectionSubmittedState(message, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchExpenseRecords(
    DelegateExpenseRecordsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final expenses = await _repo.getExpenseRecords();
      emit(DelegateExpenseRecordsLoaded(expenses, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onUpdateExpenseRecord(
    DelegateExpenseRecordUpdateRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final expense = await _repo.updateExpenseRecord(
        id: event.id,
        amount: event.amount,
        description: event.description,
      );
      emit(DelegateExpenseRecordUpdatedState(expense, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onDeleteExpenseRecord(
    DelegateExpenseRecordDeleteRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final message = await _repo.deleteExpenseRecord(event.id);
      emit(DelegateExpenseRecordDeletedState(event.id, message, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchCustomerCollectionRecords(
    DelegateCustomerCollectionRecordsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final collections = await _repo.getCustomerCollectionRecords();
      emit(DelegateCustomerCollectionRecordsLoaded(collections, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onUpdateCustomerCollectionRecord(
    DelegateCustomerCollectionRecordUpdateRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final collection = await _repo.updateCustomerCollectionRecord(
        id: event.id,
        amount: event.amount,
        notes: event.notes,
      );
      emit(DelegateCustomerCollectionRecordUpdatedState(collection, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onDeleteCustomerCollectionRecord(
    DelegateCustomerCollectionRecordDeleteRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final message = await _repo.deleteCustomerCollectionRecord(event.id);
      emit(DelegateCustomerCollectionRecordDeletedState(event.id, message, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchReportByRegion(
    DelegateReportByRegionRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final rows = await _repo.getReportByRegion(
        period: event.period,
        dateFrom: event.dateFrom,
        dateTo: event.dateTo,
      );
      emit(DelegateReportByRegionLoaded(rows, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  Future<void> _onFetchReportByProduct(
    DelegateReportByProductRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading(requestId: event.requestId));
    try {
      final rows = await _repo.getReportByProduct(
        period: event.period,
        dateFrom: event.dateFrom,
        dateTo: event.dateTo,
      );
      emit(DelegateReportByProductLoaded(rows, requestId: event.requestId));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e), requestId: event.requestId));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.', requestId: event.requestId));
    }
  }

  String _parseError(DioException e) {
    final serverMessage = e.response?.data?['message'] as String?;
    if (serverMessage != null && serverMessage.isNotEmpty) return serverMessage;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'انتهت مهلة الاتصال. تحقق من الشبكة وأعد المحاولة.';
      case DioExceptionType.connectionError:
        return 'تعذر الاتصال بالخادم. تحقق من الإنترنت.';
      default:
        return 'فشل الاتصال بالخادم.';
    }
  }
}
