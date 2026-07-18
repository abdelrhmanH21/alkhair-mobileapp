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
  /// Echoes back the [DelegateEvent.requestId] of whichever event produced
  /// this state (null for states not tied to a specific dispatch, e.g.
  /// [DelegateInitial]). This is the whole mechanism behind this bloc's
  /// systemic "was this MY request" fix — see DelegateEvent.requestId.
  ///
  /// Included in [props] (every subclass appends it) because Bloc's `emit`
  /// silently drops a state that equals the current state
  /// (`if (this.state == state && _emitted) return;` in bloc.dart) — without
  /// requestId in props, two requests that happen to resolve to identical
  /// data (e.g. two consecutive polls with no change) would collapse into a
  /// single emission, and every listener but the first to see it would never
  /// learn its own dispatch actually completed.
  final String? requestId;
  const DelegateState({this.requestId});

  @override
  List<Object?> get props => [requestId];
}

class DelegateInitial extends DelegateState {
  const DelegateInitial();
}

class DelegateLoading extends DelegateState {
  const DelegateLoading({super.requestId});
}

class DelegateLoadingLoaded extends DelegateState {
  final LoadingModel? loading;
  const DelegateLoadingLoaded(this.loading, {super.requestId});
  @override
  List<Object?> get props => [loading, requestId];
}

class DelegateLoadingConfirmedState extends DelegateState {
  final LoadingModel loading;
  const DelegateLoadingConfirmedState(this.loading, {super.requestId});
  @override
  List<Object?> get props => [loading, requestId];
}

class DelegateTruckStockLoaded extends DelegateState {
  final List<TruckStockModel> stocks;
  const DelegateTruckStockLoaded(this.stocks, {super.requestId});
  @override
  List<Object?> get props => [stocks, requestId];
}

class DelegateClientSearchResults extends DelegateState {
  final List<ClientModel> clients;
  const DelegateClientSearchResults(this.clients, {super.requestId});
  @override
  List<Object?> get props => [clients, requestId];
}

class DelegateClientCreatedState extends DelegateState {
  final ClientModel client;
  const DelegateClientCreatedState(this.client, {super.requestId});
  @override
  List<Object?> get props => [client, requestId];
}

class DelegateInvoiceSubmittedState extends DelegateState {
  final DelegateInvoiceModel invoice;
  const DelegateInvoiceSubmittedState(this.invoice, {super.requestId});
  @override
  List<Object?> get props => [invoice, requestId];
}

class DelegateInvoiceUpdatedState extends DelegateState {
  final DelegateInvoiceModel invoice;
  const DelegateInvoiceUpdatedState(this.invoice, {super.requestId});
  @override
  List<Object?> get props => [invoice, requestId];
}

class DelegateInvoicesLoaded extends DelegateState {
  final List<DelegateInvoiceModel> invoices;
  const DelegateInvoicesLoaded(this.invoices, {super.requestId});
  @override
  List<Object?> get props => [invoices, requestId];
}

class DelegateLoadingStatusUpdated extends DelegateState {
  final LoadingModel loading;
  const DelegateLoadingStatusUpdated(this.loading, {super.requestId});
  @override
  List<Object?> get props => [loading, requestId];
}

class DelegateDashboardLoaded extends DelegateState {
  final DashboardModel dashboard;
  const DelegateDashboardLoaded(this.dashboard, {super.requestId});
  @override
  List<Object?> get props => [dashboard, requestId];
}

class DelegateSellableProductsLoaded extends DelegateState {
  final List<SellableProductModel> products;
  const DelegateSellableProductsLoaded(this.products, {super.requestId});
  @override
  List<Object?> get props => [products, requestId];
}

class DelegateSalesCatalogLoaded extends DelegateState {
  final List<CatalogProductModel> products;
  const DelegateSalesCatalogLoaded(this.products, {super.requestId});
  @override
  List<Object?> get props => [products, requestId];
}

class DelegateCustomerRegionsLoaded extends DelegateState {
  final List<CustomerRegionModel> regions;
  const DelegateCustomerRegionsLoaded(this.regions, {super.requestId});
  @override
  List<Object?> get props => [regions, requestId];
}

class DelegateSettlementSummaryLoaded extends DelegateState {
  final SettlementSummaryModel summary;
  const DelegateSettlementSummaryLoaded(this.summary, {super.requestId});
  @override
  List<Object?> get props => [summary, requestId];
}

/// myShiftSummary() 404s whenever the delegate has no active/unsettled
/// loading right now — a normal, expected, non-error state (not "the
/// request failed"), so it gets its own dedicated state instead of being
/// routed through DelegateFailure. This also means any OTHER widget sharing
/// this bloc (e.g. _HomeTab, which stays mounted forever alongside
/// SettlementPage inside DelegateHomePage's IndexedStack) can no longer
/// mistake this for a real error meant for it — DelegateFailure listeners
/// simply never see it at all.
class DelegateNoActiveShift extends DelegateState {
  const DelegateNoActiveShift({super.requestId});
}

class DelegateSettlementRequestSubmittedState extends DelegateState {
  final String message;
  const DelegateSettlementRequestSubmittedState(this.message, {super.requestId});
  @override
  List<Object?> get props => [message, requestId];
}

class DelegatePenaltiesLoaded extends DelegateState {
  final List<PenaltyModel> penalties;
  const DelegatePenaltiesLoaded(this.penalties, {super.requestId});
  @override
  List<Object?> get props => [penalties, requestId];
}

class DelegateAdvancesLoaded extends DelegateState {
  final List<AdvanceModel> advances;
  const DelegateAdvancesLoaded(this.advances, {super.requestId});
  @override
  List<Object?> get props => [advances, requestId];
}

class DelegateCommissionBreakdownLoaded extends DelegateState {
  final List<CommissionDayModel> days;
  const DelegateCommissionBreakdownLoaded(this.days, {super.requestId});
  @override
  List<Object?> get props => [days, requestId];
}

class DelegateFailure extends DelegateState {
  final String message;
  const DelegateFailure(this.message, {super.requestId});
  @override
  List<Object?> get props => [message, requestId];
}

class DelegateExpenseSubmittedState extends DelegateState {
  final String message;
  const DelegateExpenseSubmittedState(this.message, {super.requestId});
  @override
  List<Object?> get props => [message, requestId];
}

class DelegateCustomerCollectionSubmittedState extends DelegateState {
  final String message;
  const DelegateCustomerCollectionSubmittedState(this.message, {super.requestId});
  @override
  List<Object?> get props => [message, requestId];
}

class DelegateExpenseRecordsLoaded extends DelegateState {
  final List<ExpenseRecordModel> expenses;
  const DelegateExpenseRecordsLoaded(this.expenses, {super.requestId});
  @override
  List<Object?> get props => [expenses, requestId];
}

class DelegateExpenseRecordUpdatedState extends DelegateState {
  final ExpenseRecordModel expense;
  const DelegateExpenseRecordUpdatedState(this.expense, {super.requestId});
  @override
  List<Object?> get props => [expense, requestId];
}

class DelegateExpenseRecordDeletedState extends DelegateState {
  final int id;
  final String message;
  const DelegateExpenseRecordDeletedState(this.id, this.message, {super.requestId});
  @override
  List<Object?> get props => [id, message, requestId];
}

class DelegateCustomerCollectionRecordsLoaded extends DelegateState {
  final List<CustomerCollectionRecordModel> collections;
  const DelegateCustomerCollectionRecordsLoaded(this.collections, {super.requestId});
  @override
  List<Object?> get props => [collections, requestId];
}

class DelegateCustomerCollectionRecordUpdatedState extends DelegateState {
  final CustomerCollectionRecordModel collection;
  const DelegateCustomerCollectionRecordUpdatedState(this.collection, {super.requestId});
  @override
  List<Object?> get props => [collection, requestId];
}

class DelegateCustomerCollectionRecordDeletedState extends DelegateState {
  final int id;
  final String message;
  const DelegateCustomerCollectionRecordDeletedState(this.id, this.message, {super.requestId});
  @override
  List<Object?> get props => [id, message, requestId];
}

class DelegateReportByRegionLoaded extends DelegateState {
  final List<RegionReportRowModel> rows;
  const DelegateReportByRegionLoaded(this.rows, {super.requestId});
  @override
  List<Object?> get props => [rows, requestId];
}

class DelegateReportByProductLoaded extends DelegateState {
  final List<ProductReportRowModel> rows;
  const DelegateReportByProductLoaded(this.rows, {super.requestId});
  @override
  List<Object?> get props => [rows, requestId];
}

/// Field-level validation failure (Laravel 422 `errors` map), e.g. the
/// phone-duplicate check in DelegateClientController::store. Kept separate
/// from [DelegateFailure] so the UI can target a specific form field instead
/// of only showing a generic snackbar.
class DelegateClientValidationFailure extends DelegateState {
  final Map<String, List<String>> errors;
  final String message;
  const DelegateClientValidationFailure(this.errors, this.message, {super.requestId});
  @override
  List<Object?> get props => [errors, message, requestId];
}
