import 'package:equatable/equatable.dart';

abstract class AdminEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AdminDashboardFetched extends AdminEvent {}

class AdminDelegatesFetched extends AdminEvent {}

class AdminShiftSummaryFetched extends AdminEvent {
  final int delegateId;
  AdminShiftSummaryFetched(this.delegateId);
  @override
  List<Object?> get props => [delegateId];
}

class AdminDelegateSettled extends AdminEvent {
  final int delegateId;
  final int treasuryId;
  final double physicalCash;
  final String? notes;
  AdminDelegateSettled({
    required this.delegateId,
    required this.treasuryId,
    required this.physicalCash,
    this.notes,
  });
  @override
  List<Object?> get props => [delegateId, treasuryId, physicalCash];
}
