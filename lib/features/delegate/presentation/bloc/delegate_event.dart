import 'package:equatable/equatable.dart';
import '../../data/models/invoice_model.dart';

abstract class DelegateEvent extends Equatable {
  static int _requestCounter = 0;

  /// Unique id for this specific dispatch, assigned once per event instance
  /// (not per event *type*). DelegateBloc echoes it back on every state that
  /// results from processing this event, so a listener sharing the bloc with
  /// other simultaneously-mounted screens (e.g. every tab in
  /// DelegateHomePage's IndexedStack, all alive forever) or with this
  /// screen's own background PollingMixin tick can tell "was this MY
  /// dispatch" apart definitively, instead of the fragile per-screen
  /// _fetchInFlight/_pollInFlight/_actionInFlight bool flags this replaces.
  /// Deliberately excluded from [props]: two otherwise-identical events
  /// (e.g. two DelegateLoadingFetched()) must keep comparing equal for any
  /// code/tests relying on Equatable equality — only DelegateBloc and
  /// RequestTracker ever read requestId directly.
  final String requestId = 'req_${_requestCounter++}';

  @override
  List<Object?> get props => [];
}

class DelegateLoadingFetched extends DelegateEvent {}

class DelegateLoadingConfirmed extends DelegateEvent {}

class DelegateTruckStockFetched extends DelegateEvent {}

class DelegateDashboardRequested extends DelegateEvent {}

class DelegateClientSearchRequested extends DelegateEvent {
  final String query;
  DelegateClientSearchRequested(this.query);
  @override
  List<Object?> get props => [query];
}

class DelegateClientCreated extends DelegateEvent {
  final String name;
  final String phone;
  final String? region;
  final int? customerRegionId;
  final double? initialBalance;
  DelegateClientCreated({
    required this.name,
    required this.phone,
    this.region,
    this.customerRegionId,
    this.initialBalance,
  });
  @override
  List<Object?> get props => [name, phone, region, customerRegionId, initialBalance];
}

class DelegateSellableProductsFetched extends DelegateEvent {
  final int? customerId;
  DelegateSellableProductsFetched({this.customerId});
  @override
  List<Object?> get props => [customerId];
}

class DelegateSalesCatalogFetched extends DelegateEvent {}

class DelegateCustomerRegionsFetched extends DelegateEvent {}

class DelegateInvoiceSubmitted extends DelegateEvent {
  final int clientId;
  final List<InvoiceSaleItem> salesItems;
  final List<InvoiceReturnItem> returnedItems;
  final double cashReceived;
  final double discountAmount;
  final double? latitude;
  final double? longitude;

  DelegateInvoiceSubmitted({
    required this.clientId,
    required this.salesItems,
    required this.returnedItems,
    required this.cashReceived,
    this.discountAmount = 0,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props =>
      [clientId, cashReceived, discountAmount, latitude, longitude];
}

class DelegateInvoiceUpdateRequested extends DelegateEvent {
  final int invoiceId;
  final List<InvoiceSaleItem> salesItems;
  final List<InvoiceReturnItem> returnedItems;
  final double cashReceived;
  final double discountAmount;

  DelegateInvoiceUpdateRequested({
    required this.invoiceId,
    required this.salesItems,
    required this.returnedItems,
    required this.cashReceived,
    this.discountAmount = 0,
  });

  @override
  List<Object?> get props => [invoiceId, cashReceived, discountAmount];
}

class DelegateInvoicesFetched extends DelegateEvent {}

class DelegateLoadingStatusUpdateRequested extends DelegateEvent {
  final int loadingId;
  final String status;
  DelegateLoadingStatusUpdateRequested({required this.loadingId, required this.status});
  @override
  List<Object?> get props => [loadingId, status];
}

class DelegateSettlementSummaryRequested extends DelegateEvent {}

class DelegateSettlementRequestSubmitted extends DelegateEvent {
  final double cashAmount;
  final double walletAmount;
  final String? notes;
  DelegateSettlementRequestSubmitted({
    required this.cashAmount,
    required this.walletAmount,
    this.notes,
  });
  @override
  List<Object?> get props => [cashAmount, walletAmount, notes];
}

class DelegatePenaltiesFetched extends DelegateEvent {}

class DelegateAdvancesFetched extends DelegateEvent {}

class DelegateCommissionBreakdownFetched extends DelegateEvent {}

class DelegateExpenseSubmitted extends DelegateEvent {
  final double amount;
  final String description;
  final int? categoryId;
  final String? notes;
  DelegateExpenseSubmitted({
    required this.amount,
    required this.description,
    this.categoryId,
    this.notes,
  });
  @override
  List<Object?> get props => [amount, description, categoryId, notes];
}

class DelegateCustomerCollectionSubmitted extends DelegateEvent {
  final int customerId;
  final double amount;
  final String paymentMethod;
  final String? notes;
  DelegateCustomerCollectionSubmitted({
    required this.customerId,
    required this.amount,
    required this.paymentMethod,
    this.notes,
  });
  @override
  List<Object?> get props => [customerId, amount, paymentMethod, notes];
}

class DelegateExpenseRecordsFetched extends DelegateEvent {}

class DelegateExpenseRecordUpdateRequested extends DelegateEvent {
  final int id;
  final double amount;
  final String description;
  DelegateExpenseRecordUpdateRequested({
    required this.id,
    required this.amount,
    required this.description,
  });
  @override
  List<Object?> get props => [id, amount, description];
}

class DelegateExpenseRecordDeleteRequested extends DelegateEvent {
  final int id;
  DelegateExpenseRecordDeleteRequested({required this.id});
  @override
  List<Object?> get props => [id];
}

class DelegateCustomerCollectionRecordsFetched extends DelegateEvent {}

class DelegateCustomerCollectionRecordUpdateRequested extends DelegateEvent {
  final int id;
  final double amount;
  final String? notes;
  DelegateCustomerCollectionRecordUpdateRequested({
    required this.id,
    required this.amount,
    this.notes,
  });
  @override
  List<Object?> get props => [id, amount, notes];
}

class DelegateCustomerCollectionRecordDeleteRequested extends DelegateEvent {
  final int id;
  DelegateCustomerCollectionRecordDeleteRequested({required this.id});
  @override
  List<Object?> get props => [id];
}

class DelegateReportByRegionRequested extends DelegateEvent {
  final String? period;
  final String? dateFrom;
  final String? dateTo;
  DelegateReportByRegionRequested({this.period, this.dateFrom, this.dateTo});
  @override
  List<Object?> get props => [period, dateFrom, dateTo];
}

class DelegateReportByProductRequested extends DelegateEvent {
  final String? period;
  final String? dateFrom;
  final String? dateTo;
  DelegateReportByProductRequested({this.period, this.dateFrom, this.dateTo});
  @override
  List<Object?> get props => [period, dateFrom, dateTo];
}
