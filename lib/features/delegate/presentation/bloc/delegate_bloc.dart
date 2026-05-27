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
    on<DelegateClientSearchRequested>(_onSearchClients);
    on<DelegateClientCreated>(_onCreateClient);
    on<DelegateInvoiceSubmitted>(_onSubmitInvoice);
    on<DelegateInvoicesFetched>(_onFetchInvoices);
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
        initialBalance: event.initialBalance,
      );
      emit(DelegateClientCreatedState(client));
    } on DioException catch (e) {
      emit(DelegateFailure(_parseError(e)));
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
    }
  }

  String _parseError(DioException e) =>
      e.response?.data?['message'] as String? ?? 'فشل الاتصال بالخادم.';
}
