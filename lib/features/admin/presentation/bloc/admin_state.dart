import 'package:equatable/equatable.dart';
import '../../data/models/admin_models.dart';
// ignore_for_file: always_use_package_imports

abstract class AdminState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AdminInitial extends AdminState {}
class AdminLoading extends AdminState {}

class AdminDashboardLoaded extends AdminState {
  final DashboardStatsModel stats;
  AdminDashboardLoaded(this.stats);
  @override
  List<Object?> get props => [stats];
}

class AdminDelegatesLoaded extends AdminState {
  final List<DelegateModel> delegates;
  AdminDelegatesLoaded(this.delegates);
  @override
  List<Object?> get props => [delegates];
}

class AdminShiftSummaryLoaded extends AdminState {
  final ShiftSummaryModel summary;
  AdminShiftSummaryLoaded(this.summary);
  @override
  List<Object?> get props => [summary];
}

class AdminSettlementSuccess extends AdminState {
  final Map<String, dynamic> result;
  AdminSettlementSuccess(this.result);
  @override
  List<Object?> get props => [result];
}

class AdminLoadingFormLoaded extends AdminState {
  final List<DelegateModel> delegates;
  final List<SimpleWarehouseModel> warehouses;
  final List<SimpleProductModel> products;

  AdminLoadingFormLoaded({
    required this.delegates,
    required this.warehouses,
    required this.products,
  });

  @override
  List<Object?> get props => [delegates, warehouses, products];
}

class AdminLoadingCreatedSuccess extends AdminState {
  final String message;
  AdminLoadingCreatedSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class AdminFailure extends AdminState {
  final String message;
  AdminFailure(this.message);
  @override
  List<Object?> get props => [message];
}
