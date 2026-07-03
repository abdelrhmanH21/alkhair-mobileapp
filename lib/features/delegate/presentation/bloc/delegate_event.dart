import 'package:equatable/equatable.dart';
import '../../data/models/invoice_model.dart';

abstract class DelegateEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class DelegateLoadingFetched extends DelegateEvent {}

class DelegateLoadingConfirmed extends DelegateEvent {}

class DelegateTruckStockFetched extends DelegateEvent {}

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
  final double? latitude;
  final double? longitude;

  DelegateInvoiceSubmitted({
    required this.clientId,
    required this.salesItems,
    required this.returnedItems,
    required this.cashReceived,
    this.latitude,
    this.longitude,
  });

  @override
  List<Object?> get props => [clientId, cashReceived, latitude, longitude];
}

class DelegateInvoicesFetched extends DelegateEvent {}

class DelegateLoadingStatusUpdateRequested extends DelegateEvent {
  final int loadingId;
  final String status;
  DelegateLoadingStatusUpdateRequested({required this.loadingId, required this.status});
  @override
  List<Object?> get props => [loadingId, status];
}
