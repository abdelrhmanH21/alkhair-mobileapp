import 'package:equatable/equatable.dart';
import '../../data/models/admin_models.dart';

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

class AdminFailure extends AdminState {
  final String message;
  AdminFailure(this.message);
  @override
  List<Object?> get props => [message];
}
