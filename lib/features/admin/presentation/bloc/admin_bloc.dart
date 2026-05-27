import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/datasources/admin_remote_datasource.dart';
import 'admin_event.dart';
import 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final AdminRemoteDataSource _remote;
  AdminBloc(this._remote) : super(AdminInitial()) {
    on<AdminDashboardFetched>(_onDashboard);
    on<AdminDelegatesFetched>(_onDelegates);
    on<AdminShiftSummaryFetched>(_onShiftSummary);
    on<AdminDelegateSettled>(_onSettle);
  }

  Future<void> _onDashboard(
      AdminDashboardFetched e, Emitter<AdminState> emit) async {
    emit(AdminLoading());
    try {
      final stats = await _remote.fetchDashboard();
      emit(AdminDashboardLoaded(stats));
    } on DioException catch (e) {
      emit(AdminFailure(_msg(e)));
    }
  }

  Future<void> _onDelegates(
      AdminDelegatesFetched e, Emitter<AdminState> emit) async {
    emit(AdminLoading());
    try {
      final delegates = await _remote.fetchDelegates();
      emit(AdminDelegatesLoaded(delegates));
    } on DioException catch (e) {
      emit(AdminFailure(_msg(e)));
    }
  }

  Future<void> _onShiftSummary(
      AdminShiftSummaryFetched e, Emitter<AdminState> emit) async {
    emit(AdminLoading());
    try {
      final summary = await _remote.fetchShiftSummary(e.delegateId);
      emit(AdminShiftSummaryLoaded(summary));
    } on DioException catch (e) {
      emit(AdminFailure(_msg(e)));
    }
  }

  Future<void> _onSettle(
      AdminDelegateSettled e, Emitter<AdminState> emit) async {
    emit(AdminLoading());
    try {
      final result = await _remote.settleDelegate(
        delegateId: e.delegateId,
        treasuryId: e.treasuryId,
        physicalCash: e.physicalCash,
        notes: e.notes,
      );
      emit(AdminSettlementSuccess(result));
    } on DioException catch (e) {
      emit(AdminFailure(_msg(e)));
    }
  }

  String _msg(DioException e) =>
      e.response?.data?['message'] as String? ?? 'فشل الاتصال بالخادم.';
}
