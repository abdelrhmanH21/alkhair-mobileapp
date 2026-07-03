import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/loading_model.dart';
import '../models/client_model.dart';
import '../models/invoice_model.dart';
import '../models/sellable_product_model.dart';
import '../models/catalog_product_model.dart';
import '../models/customer_region_model.dart';

abstract class DelegateRemoteDataSource {
  Future<LoadingModel?> fetchCurrentLoading();
  Future<LoadingModel> confirmLoading();
  Future<List<TruckStockModel>> fetchTruckStock();
  Future<List<ClientModel>> searchClients(String query);
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    int? customerRegionId,
    double? initialBalance,
  });
  Future<List<SellableProductModel>> fetchSellableProducts({int? customerId});
  Future<List<CatalogProductModel>> fetchSalesCatalogProducts();
  Future<List<CustomerRegionModel>> fetchCustomerRegions();
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double? latitude,
    double? longitude,
  });
  Future<List<DelegateInvoiceModel>> fetchInvoices();
  Future<DelegateInvoiceModel> fetchInvoice(int id);
  Future<LoadingModel> updateLoadingStatus(int id, String status);
}

class DelegateRemoteDataSourceImpl implements DelegateRemoteDataSource {
  final ApiClient _client;
  DelegateRemoteDataSourceImpl(this._client);

  @override
  Future<LoadingModel?> fetchCurrentLoading() async {
    final res = await _client.dio.get(ApiEndpoints.delegateLoading);
    final data = res.data['data'];
    if (data == null) return null;
    return LoadingModel.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<LoadingModel> confirmLoading() async {
    final res = await _client.dio.post(ApiEndpoints.delegateLoadingConfirm);
    return LoadingModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<TruckStockModel>> fetchTruckStock() async {
    final res = await _client.dio.get(ApiEndpoints.delegateTruckStock);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => TruckStockModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ClientModel>> searchClients(String query) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegateClientSearch,
      queryParameters: {'query': query},
    );
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ClientModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    int? customerRegionId,
    double? initialBalance,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.delegateClients, data: {
      'name': name,
      'phone': phone,
      if (customerRegionId != null) 'customer_region_id': customerRegionId,
      if (region != null) 'region': region,
      if (initialBalance != null) 'initial_outstanding_balance': initialBalance,
    });
    return ClientModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<SellableProductModel>> fetchSellableProducts({int? customerId}) async {
    final res = await _client.dio.get(
      ApiEndpoints.delegateSellableProducts,
      queryParameters: {if (customerId != null) 'customer_id': customerId},
    );
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => SellableProductModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CatalogProductModel>> fetchSalesCatalogProducts() async {
    final res = await _client.dio.get(
      ApiEndpoints.products,
      queryParameters: {'is_sales_item': true, 'per_page': 500},
    );
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => CatalogProductModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CustomerRegionModel>> fetchCustomerRegions() async {
    final res = await _client.dio.get(
      ApiEndpoints.customerRegions,
      queryParameters: {'is_active': true, 'per_page': 500},
    );
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => CustomerRegionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double? latitude,
    double? longitude,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.delegateInvoice, data: {
      'client_id': clientId,
      if (salesItems.isNotEmpty) 'sales_items': salesItems,
      if (returnedItems.isNotEmpty) 'returned_items': returnedItems,
      'cash_received': cashReceived,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return DelegateInvoiceModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<DelegateInvoiceModel>> fetchInvoices() async {
    final res = await _client.dio.get(ApiEndpoints.delegateInvoices);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => DelegateInvoiceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<DelegateInvoiceModel> fetchInvoice(int id) async {
    final res = await _client.dio.get('${ApiEndpoints.delegateInvoices}/$id');
    return DelegateInvoiceModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<LoadingModel> updateLoadingStatus(int id, String status) async {
    final res = await _client.dio.post(
      ApiEndpoints.delegateLoadingStatus(id),
      data: {'status': status},
    );
    return LoadingModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }
}
