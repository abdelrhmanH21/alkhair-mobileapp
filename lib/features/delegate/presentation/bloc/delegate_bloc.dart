import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../domain/repositories/delegate_repository.dart';
import '../../../../core/utils/gps_service.dart';
import 'delegate_event.dart';
import 'delegate_state.dart';

class DelegateBloc extends Bloc<DelegateEvent, DelegateState> {
  final DelegateRepository _repo;
  final GpsService _gps;

  DelegateBloc(this._repo, this._gps) : super(DelegateInitial()) {
    on<DelegateLoadingFetched>(_onFetchLoading);
    on<DelegateLoadingConfirmed>(_onConfirmLoading);
    on<DelegateTruckStockFetched>(_onFetchTruckStock);
    on<DelegateDashboardRequested>(_onFetchDashboard);
    on<DelegateClientSearchRequested>(_onSearchClients);
    on<DelegateClientCreated>(_onCreateClient);
    on<DelegateInvoiceSubmitted>(_onSubmitInvoice);
    on<DelegateInvoicesFetched>(_onFetchInvoices);
    on<DelegateLoadingStatusUpdateRequested>(_onUpdateLoadingStatus);
    on<DelegateSellableProductsFetched>(_onFetchSellableProducts);
    on<DelegateSalesCatalogFetched>(_onFetchSalesCatalog);
    on<DelegateCustomerRegionsFetched>(_onFetchCustomerRegions);
    on<DelegateSettlementSummaryRequested>(_onFetchSettlementSummary);
    on<DelegateSettlementRequestSubmitted>(_onSubmitSettlementRequest);
    on<DelegatePenaltiesFetched>(_onFetchPenalties);
    on<DelegateAdvancesFetched>(_onFetchAdvances);
    on<DelegateCommissionBreakdownFetched>(_onFetchCommissionBreakdown);
  }

  Future<void> _onFetchLoading(
    DelegateLoadingFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final loading = await _repo.getCurrentLoading();
      emit(DelegateLoadingLoaded(loading));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onConfirmLoading(
    DelegateLoadingConfirmed event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final loading = await _repo.confirmLoading();
      emit(DelegateLoadingConfirmedState(loading));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchTruckStock(
    DelegateTruckStockFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final stocks = await _repo.getTruckStock();
      emit(DelegateTruckStockLoaded(stocks));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchDashboard(
    DelegateDashboardRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final dashboard = await _repo.getDashboard();
      emit(DelegateDashboardLoaded(dashboard));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onSearchClients(
    DelegateClientSearchRequested event,
    Emitter<DelegateState> emit,
  ) async {
    try {
      final clients = await _repo.searchClients(event.query);
      emit(DelegateClientSearchResults(clients));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ في البحث. حاول مرة أخرى.'));
    }
  }

  Future<void> _onCreateClient(
    DelegateClientCreated event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final client = await _repo.createClient(
        name: event.name,
        phone: event.phone,
        region: event.region,
        customerRegionId: event.customerRegionId,
        initialBalance: event.initialBalance,
      );
      emit(DelegateClientCreatedState(client));
    } on DioException catch (e) {
      final fieldErrors = e.response?.data?['errors'] as Map<String, dynamic>?;
      if (e.response?.statusCode == 422 && fieldErrors != null) {
        emit(DelegateClientValidationFailure(
          fieldErrors.map((k, v) => MapEntry(k, (v as List).map((s) => s.toString()).toList())),
          _parseError(e),
        ));
      } else {
        emit(DelegateFailure(_parseError(e)));
      }
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchSellableProducts(
    DelegateSellableProductsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final products = await _repo.getSellableProducts(customerId: event.customerId);
      emit(DelegateSellableProductsLoaded(products));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchSalesCatalog(
    DelegateSalesCatalogFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final products = await _repo.getSalesCatalogProducts();
      emit(DelegateSalesCatalogLoaded(products));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchCustomerRegions(
    DelegateCustomerRegionsFetched event,
    Emitter<DelegateState> emit,
  ) async {
    try {
      final regions = await _repo.getCustomerRegions();
      emit(DelegateCustomerRegionsLoaded(regions));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onSubmitInvoice(
    DelegateInvoiceSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
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
              })
          .toList();

      final invoice = await _repo.submitInvoice(
        clientId: event.clientId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: event.cashReceived,
        latitude: coords.lat,
        longitude: coords.lng,
      );
      emit(DelegateInvoiceSubmittedState(invoice));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchInvoices(
    DelegateInvoicesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final invoices = await _repo.getInvoices();
      emit(DelegateInvoicesLoaded(invoices));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onUpdateLoadingStatus(
    DelegateLoadingStatusUpdateRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final loading = await _repo.updateLoadingStatus(event.loadingId, event.status);
      emit(DelegateLoadingStatusUpdated(loading));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchSettlementSummary(
    DelegateSettlementSummaryRequested event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final summary = await _repo.getSettlementSummary();
      emit(DelegateSettlementSummaryLoaded(summary));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onSubmitSettlementRequest(
    DelegateSettlementRequestSubmitted event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      await _repo.submitSettlementRequest(
        cashAmount: event.cashAmount,
        walletAmount: event.walletAmount,
        notes: event.notes,
      );
      emit(DelegateSettlementRequestSubmittedState(
          'تم إرسال طلب التسليم، بانتظار تأكيد الإدارة.'));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchPenalties(
    DelegatePenaltiesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final penalties = await _repo.getPenalties();
      emit(DelegatePenaltiesLoaded(penalties));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchAdvances(
    DelegateAdvancesFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final advances = await _repo.getAdvances();
      emit(DelegateAdvancesLoaded(advances));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
    }
  }

  Future<void> _onFetchCommissionBreakdown(
    DelegateCommissionBreakdownFetched event,
    Emitter<DelegateState> emit,
  ) async {
    emit(DelegateLoading());
    try {
      final days = await _repo.getCommissionBreakdown();
      emit(DelegateCommissionBreakdownLoaded(days));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
    } catch (_) {
      emit(DelegateFailure('حدث خطأ غير متوقع. حاول مرة أخرى.'));
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
