import '../datasources/delegate_remote_datasource.dart';
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
import '../../domain/repositories/delegate_repository.dart';

class DelegateRepositoryImpl implements DelegateRepository {
  final DelegateRemoteDataSource _remote;
  DelegateRepositoryImpl(this._remote);

  @override
  Future<LoadingModel?> getCurrentLoading() => _remote.fetchCurrentLoading();

  @override
  Future<DashboardModel> getDashboard() => _remote.fetchDashboard();

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

  @override
  Future<SettlementSummaryModel> getSettlementSummary() =>
      _remote.fetchSettlementSummary();

  @override
  Future<void> submitSettlementRequest({
    required double cashAmount,
    required double walletAmount,
    String? notes,
  }) =>
      _remote.submitSettlementRequest(
        cashAmount: cashAmount,
        walletAmount: walletAmount,
        notes: notes,
      );

  @override
  Future<List<PenaltyModel>> getPenalties() => _remote.fetchPenalties();

  @override
  Future<List<AdvanceModel>> getAdvances() => _remote.fetchAdvances();

  @override
  Future<List<CommissionDayModel>> getCommissionBreakdown() =>
      _remote.fetchCommissionBreakdown();

  @override
  Future<String> submitExpense({
    required double amount,
    required String description,
    int? categoryId,
    String? notes,
  }) =>
      _remote.submitExpense(
        amount: amount,
        description: description,
        categoryId: categoryId,
        notes: notes,
      );

  @override
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) =>
      _remote.submitCustomerCollection(
        customerId: customerId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
      );

  @override
  Future<List<ExpenseRecordModel>> getExpenseRecords() => _remote.fetchExpenseRecords();

  @override
  Future<ExpenseRecordModel> updateExpenseRecord({
    required int id,
    required double amount,
    required String description,
  }) =>
      _remote.updateExpenseRecord(id: id, amount: amount, description: description);

  @override
  Future<List<CustomerCollectionRecordModel>> getCustomerCollectionRecords() =>
      _remote.fetchCustomerCollectionRecords();

  @override
  Future<CustomerCollectionRecordModel> updateCustomerCollectionRecord({
    required int id,
    required double amount,
    String? notes,
  }) =>
      _remote.updateCustomerCollectionRecord(id: id, amount: amount, notes: notes);

  @override
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo}) =>
      _remote.fetchReportByRegion(period: period, dateFrom: dateFrom, dateTo: dateTo);

  @override
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo}) =>
      _remote.fetchReportByProduct(period: period, dateFrom: dateFrom, dateTo: dateTo);
}
