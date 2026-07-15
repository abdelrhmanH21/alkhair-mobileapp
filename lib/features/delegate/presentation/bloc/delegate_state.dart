import 'package:equatable/equatable.dart';
import '../../data/models/loading_model.dart';
import '../../data/models/client_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/dashboard_model.dart';
import '../../data/models/sellable_product_model.dart';
import '../../data/models/catalog_product_model.dart';
import '../../data/models/customer_region_model.dart';
import '../../data/models/settlement_summary_model.dart';
import '../../data/models/breakdown_models.dart';
import '../../data/models/transaction_record_models.dart';
import '../../data/models/report_models.dart';

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

class DelegateSellableProductsLoaded extends DelegateState {
  final List<SellableProductModel> products;
  DelegateSellableProductsLoaded(this.products);
  @override
  List<Object?> get props => [products];
}

class DelegateSalesCatalogLoaded extends DelegateState {
  final List<CatalogProductModel> products;
  DelegateSalesCatalogLoaded(this.products);
  @override
  List<Object?> get props => [products];
}

class DelegateCustomerRegionsLoaded extends DelegateState {
  final List<CustomerRegionModel> regions;
  DelegateCustomerRegionsLoaded(this.regions);
  @override
  List<Object?> get props => [regions];
}

class DelegateSettlementSummaryLoaded extends DelegateState {
  final SettlementSummaryModel summary;
  DelegateSettlementSummaryLoaded(this.summary);
  @override
  List<Object?> get props => [summary];
}

/// myShiftSummary() 404s whenever the delegate has no active/unsettled
/// loading right now — a normal, expected, non-error state (not "the
/// request failed"), so it gets its own dedicated state instead of being
/// routed through DelegateFailure. This also means any OTHER widget sharing
/// this bloc (e.g. _HomeTab, which stays mounted forever alongside
/// SettlementPage inside DelegateHomePage's IndexedStack) can no longer
/// mistake this for a real error meant for it — DelegateFailure listeners
/// simply never see it at all.
class DelegateNoActiveShift extends DelegateState {}

class DelegateSettlementRequestSubmittedState extends DelegateState {
  final String message;
  DelegateSettlementRequestSubmittedState(this.message);
  @override
  List<Object?> get props => [message];
}

class DelegatePenaltiesLoaded extends DelegateState {
  final List<PenaltyModel> penalties;
  DelegatePenaltiesLoaded(this.penalties);
  @override
  List<Object?> get props => [penalties];
}

class DelegateAdvancesLoaded extends DelegateState {
  final List<AdvanceModel> advances;
  DelegateAdvancesLoaded(this.advances);
  @override
  List<Object?> get props => [advances];
}

class DelegateCommissionBreakdownLoaded extends DelegateState {
  final List<CommissionDayModel> days;
  DelegateCommissionBreakdownLoaded(this.days);
  @override
  List<Object?> get props => [days];
}

class DelegateFailure extends DelegateState {
  final String message;
  DelegateFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class DelegateExpenseSubmittedState extends DelegateState {
  final String message;
  DelegateExpenseSubmittedState(this.message);
  @override
  List<Object?> get props => [message];
}

class DelegateCustomerCollectionSubmittedState extends DelegateState {
  final String message;
  DelegateCustomerCollectionSubmittedState(this.message);
  @override
  List<Object?> get props => [message];
}

class DelegateExpenseRecordsLoaded extends DelegateState {
  final List<ExpenseRecordModel> expenses;
  DelegateExpenseRecordsLoaded(this.expenses);
  @override
  List<Object?> get props => [expenses];
}

class DelegateExpenseRecordUpdatedState extends DelegateState {
  final ExpenseRecordModel expense;
  DelegateExpenseRecordUpdatedState(this.expense);
  @override
  List<Object?> get props => [expense];
}

class DelegateCustomerCollectionRecordsLoaded extends DelegateState {
  final List<CustomerCollectionRecordModel> collections;
  DelegateCustomerCollectionRecordsLoaded(this.collections);
  @override
  List<Object?> get props => [collections];
}

class DelegateCustomerCollectionRecordUpdatedState extends DelegateState {
  final CustomerCollectionRecordModel collection;
  DelegateCustomerCollectionRecordUpdatedState(this.collection);
  @override
  List<Object?> get props => [collection];
}

class DelegateReportByRegionLoaded extends DelegateState {
  final List<RegionReportRowModel> rows;
  DelegateReportByRegionLoaded(this.rows);
  @override
  List<Object?> get props => [rows];
}

class DelegateReportByProductLoaded extends DelegateState {
  final List<ProductReportRowModel> rows;
  DelegateReportByProductLoaded(this.rows);
  @override
  List<Object?> get props => [rows];
}

/// Field-level validation failure (Laravel 422 `errors` map), e.g. the
/// phone-duplicate check in DelegateClientController::store. Kept separate
/// from [DelegateFailure] so the UI can target a specific form field instead
/// of only showing a generic snackbar.
class DelegateClientValidationFailure extends DelegateState {
  final Map<String, List<String>> errors;
  final String message;
  DelegateClientValidationFailure(this.errors, this.message);
  @override
  List<Object?> get props => [errors, message];
}
