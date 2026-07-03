import 'package:equatable/equatable.dart';
import '../../data/models/loading_model.dart';
import '../../data/models/client_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/dashboard_model.dart';

abstract class DelegateState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DelegateInitial extends DelegateState {}

class DelegateLoading extends DelegateState {}

class DelegateLoadingLoaded extends DelegateState {
  final LoadingModel? loading;
  DelegateLoadingLoaded(this.loading);
  @override
  List<Object?> get props => [loading];
}

class DelegateLoadingConfirmedState extends DelegateState {
  final LoadingModel loading;
  DelegateLoadingConfirmedState(this.loading);
  @override
  List<Object?> get props => [loading];
}

class DelegateTruckStockLoaded extends DelegateState {
  final List<TruckStockModel> stocks;
  DelegateTruckStockLoaded(this.stocks);
  @override
  List<Object?> get props => [stocks];
}

class DelegateClientSearchResults extends DelegateState {
  final List<ClientModel> clients;
  DelegateClientSearchResults(this.clients);
  @override
  List<Object?> get props => [clients];
}

class DelegateClientCreatedState extends DelegateState {
  final ClientModel client;
  DelegateClientCreatedState(this.client);
  @override
  List<Object?> get props => [client];
}

class DelegateInvoiceSubmittedState extends DelegateState {
  final DelegateInvoiceModel invoice;
  DelegateInvoiceSubmittedState(this.invoice);
  @override
  List<Object?> get props => [invoice];
}

class DelegateInvoicesLoaded extends DelegateState {
  final List<DelegateInvoiceModel> invoices;
  DelegateInvoicesLoaded(this.invoices);
  @override
  List<Object?> get props => [invoices];
}

class DelegateLoadingStatusUpdated extends DelegateState {
  final LoadingModel loading;
  DelegateLoadingStatusUpdated(this.loading);
  @override
  List<Object?> get props => [loading];
}

class DelegateDashboardLoaded extends DelegateState {
  final DashboardModel dashboard;
  DelegateDashboardLoaded(this.dashboard);
  @override
  List<Object?> get props => [dashboard];
}

class DelegateFailure extends DelegateState {
  final String message;
  DelegateFailure(this.message);
  @override
  List<Object?> get props => [message];
}
