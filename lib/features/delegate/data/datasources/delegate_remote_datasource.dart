import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/loading_model.dart';
import '../models/client_model.dart';
import '../models/invoice_model.dart';
import '../models/dashboard_model.dart';
import '../models/sellable_product_model.dart';
import '../models/catalog_product_model.dart';
import '../models/customer_region_model.dart';
import '../models/settlement_summary_model.dart';
import '../models/breakdown_models.dart';
import '../models/transaction_record_models.dart';
import '../models/report_models.dart';

abstract class DelegateRemoteDataSource {
  Future<LoadingModel?> fetchCurrentLoading();
  Future<LoadingModel> confirmLoading();
  Future<List<TruckStockModel>> fetchTruckStock();
  Future<DashboardModel> fetchDashboard();
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
  Future<SettlementSummaryModel> fetchSettlementSummary();
  Future<void> submitSettlementRequest({
    required double cashAmount,
    required double walletAmount,
    String? notes,
  });
  Future<List<PenaltyModel>> fetchPenalties();
  Future<List<AdvanceModel>> fetchAdvances();
  Future<List<CommissionDayModel>> fetchCommissionBreakdown();
  Future<String> submitExpense({
    required double amount,
    required String description,
    int? categoryId,
    String? notes,
  });
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
  });
  Future<List<ExpenseRecordModel>> fetchExpenseRecords();
  Future<ExpenseRecordModel> updateExpenseRecord({
    required int id,
    required double amount,
    required String description,
  });
  Future<List<CustomerCollectionRecordModel>> fetchCustomerCollectionRecords();
  Future<CustomerCollectionRecordModel> updateCustomerCollectionRecord({
    required int id,
    required double amount,
    String? notes,
  });
  Future<List<RegionReportRowModel>> fetchReportByRegion({String? period, String? dateFrom, String? dateTo});
  Future<List<ProductReportRowModel>> fetchReportByProduct({String? period, String? dateFrom, String? dateTo});
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
  Future<DashboardModel> fetchDashboard() async {
    final res = await _client.dio.get(ApiEndpoints.delegateDashboard);
    return DashboardModel.fromJson(res.data['data'] as Map<String, dynamic>);
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

  @override
  Future<SettlementSummaryModel> fetchSettlementSummary() async {
    final res = await _client.dio.get(ApiEndpoints.delegateShiftSummary);
    return SettlementSummaryModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<void> submitSettlementRequest({
    required double cashAmount,
    required double walletAmount,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.delegateSettlementRequest, data: {
      'cash_amount': cashAmount,
      'wallet_amount': walletAmount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  @override
  Future<List<PenaltyModel>> fetchPenalties() async {
    final res = await _client.dio.get(ApiEndpoints.delegatePenalties);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => PenaltyModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<AdvanceModel>> fetchAdvances() async {
    final res = await _client.dio.get(ApiEndpoints.delegateAdvances);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => AdvanceModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<CommissionDayModel>> fetchCommissionBreakdown() async {
    final res = await _client.dio.get(ApiEndpoints.delegateCommissionBreakdown);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => CommissionDayModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<String> submitExpense({
    required double amount,
    required String description,
    int? categoryId,
    String? notes,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.delegateExpenses, data: {
      'amount': amount,
      'description': description,
      if (categoryId != null) 'category_id': categoryId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return (res.data['message'] as String?) ?? 'تم تسجيل المصروف بنجاح.';
  }

  @override
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.delegateCustomerCollections, data: {
      'customer_id': customerId,
      'amount': amount,
      'payment_method': paymentMethod,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return (res.data['message'] as String?) ?? 'تم تسجيل التحصيل بنجاح.';
  }

  @override
  Future<List<ExpenseRecordModel>> fetchExpenseRecords() async {
    final res = await _client.dio.get(ApiEndpoints.delegateExpenses);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ExpenseRecordModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<ExpenseRecordModel> updateExpenseRecord({
    required int id,
    required double amount,
    required String description,
  }) async {
    final res = await _client.dio.put(ApiEndpoints.delegateExpense(id), data: {
      'amount': amount,
      'description': description,
    });
    return ExpenseRecordModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<CustomerCollectionRecordModel>> fetchCustomerCollectionRecords() async {
    final res = await _client.dio.get(ApiEndpoints.delegateCustomerCollections);
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => CustomerCollectionRecordModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<CustomerCollectionRecordModel> updateCustomerCollectionRecord({
    required int id,
    required double amount,
    String? notes,
  }) async {
    final res = await _client.dio.put(ApiEndpoints.delegateCustomerCollection(id), data: {
      'amount': amount,
      if (notes != null) 'notes': notes,
    });
    return CustomerCollectionRecordModel.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<RegionReportRowModel>> fetchReportByRegion({String? period, String? dateFrom, String? dateTo}) async {
    final res = await _client.dio.get(ApiEndpoints.delegateReportsByRegion, queryParameters: {
      if (period != null) 'period': period,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => RegionReportRowModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<ProductReportRowModel>> fetchReportByProduct({String? period, String? dateFrom, String? dateTo}) async {
    final res = await _client.dio.get(ApiEndpoints.delegateReportsByProduct, queryParameters: {
      if (period != null) 'period': period,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    final list = res.data['data'] as List? ?? [];
    return list.map((e) => ProductReportRowModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
