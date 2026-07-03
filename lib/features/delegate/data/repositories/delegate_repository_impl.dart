import '../datasources/delegate_remote_datasource.dart';
import '../models/loading_model.dart';
import '../models/client_model.dart';
import '../models/invoice_model.dart';
import '../models/sellable_product_model.dart';
import '../models/catalog_product_model.dart';
import '../models/customer_region_model.dart';
import '../../domain/repositories/delegate_repository.dart';

class DelegateRepositoryImpl implements DelegateRepository {
  final DelegateRemoteDataSource _remote;
  DelegateRepositoryImpl(this._remote);

  @override
  Future<LoadingModel?> getCurrentLoading() => _remote.fetchCurrentLoading();

  @override
  Future<LoadingModel> confirmLoading() => _remote.confirmLoading();

  @override
  Future<List<TruckStockModel>> getTruckStock() => _remote.fetchTruckStock();

  @override
  Future<List<ClientModel>> searchClients(String query) =>
      _remote.searchClients(query);

  @override
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    int? customerRegionId,
    double? initialBalance,
  }) =>
      _remote.createClient(
        name: name,
        phone: phone,
        region: region,
        customerRegionId: customerRegionId,
        initialBalance: initialBalance,
      );

  @override
  Future<List<SellableProductModel>> getSellableProducts({int? customerId}) =>
      _remote.fetchSellableProducts(customerId: customerId);

  @override
  Future<List<CatalogProductModel>> getSalesCatalogProducts() =>
      _remote.fetchSalesCatalogProducts();

  @override
  Future<List<CustomerRegionModel>> getCustomerRegions() =>
      _remote.fetchCustomerRegions();

  @override
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double? latitude,
    double? longitude,
  }) =>
      _remote.submitInvoice(
        clientId: clientId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: cashReceived,
        latitude: latitude,
        longitude: longitude,
      );

  @override
  Future<List<DelegateInvoiceModel>> getInvoices() => _remote.fetchInvoices();

  @override
  Future<LoadingModel> updateLoadingStatus(int id, String status) =>
      _remote.updateLoadingStatus(id, status);
}
