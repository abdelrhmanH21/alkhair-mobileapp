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
import '../models/customer_invoice_history_model.dart';
import '../../../../core/utils/offline_cache_service.dart';
import '../../domain/repositories/delegate_repository.dart';

/// Cache keys for the read endpoints Phase 1 offline support covers — see
/// OfflineCacheService. A delegate only ever has one active loading at a
/// time, so these are single fixed slots (not keyed per-loading-id): the
/// cached snapshot is always "whatever this device last saw", which is
/// exactly the one loading/truck-stock/etc. that matters right now.
const _kCurrentLoading = 'current_loading';
const _kTruckStock = 'truck_stock';
const _kDashboard = 'delegate_dashboard';
const _kSellableProducts = 'sellable_products';
const _kCustomerList = 'customer_list';

class DelegateRepositoryImpl implements DelegateRepository {
  final DelegateRemoteDataSource _remote;
  final OfflineCacheService _cache;
  DelegateRepositoryImpl(this._remote, this._cache);

  @override
  Future<LoadingModel?> getCurrentLoading() async {
    final loading = await _remote.fetchCurrentLoading();
    if (loading != null) {
      await _cache.set(_kCurrentLoading, loading.toJson());
    } else {
      // A confirmed-live "no active loading right now" (e.g. right after
      // settlement) must drop any earlier cached loading — otherwise the
      // NEXT time this device opens offline, it would keep showing a
      // since-settled loading as if it were still current.
      await _cache.clear(_kCurrentLoading);
    }
    return loading;
  }

  @override
  LoadingModel? getCachedLoading() {
    final json = _cache.get(_kCurrentLoading) as Map<String, dynamic>?;
    if (json == null) return null;
    try {
      return LoadingModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DashboardModel> getDashboard() async {
    final dashboard = await _remote.fetchDashboard();
    await _cache.set(_kDashboard, dashboard.toJson());
    return dashboard;
  }

  @override
  DashboardModel? getCachedDashboard() {
    final json = _cache.get(_kDashboard) as Map<String, dynamic>?;
    if (json == null) return null;
    try {
      return DashboardModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LoadingModel> confirmLoading() => _remote.confirmLoading();

  @override
  Future<List<TruckStockModel>> getTruckStock() async {
    final stocks = await _remote.fetchTruckStock();
    await _cache.set(_kTruckStock, stocks.map((s) => s.toJson()).toList());
    return stocks;
  }

  @override
  List<TruckStockModel> getCachedTruckStock() {
    final list = _cache.get(_kTruckStock) as List?;
    if (list == null) return [];
    try {
      return list.map((e) => TruckStockModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ClientModel>> searchClients(String query) async {
    try {
      final results = await _remote.searchClients(query);
      // Only the empty-query "browse everyone" call represents the full
      // customer list — per-keystroke query results are a subset and would
      // corrupt the cache if written here.
      if (query.trim().isEmpty) {
        await _cache.set(_kCustomerList, results.map((c) => c.toJson()).toList());
      }
      return results;
    } catch (_) {
      // Offline (or the request otherwise failed): fall back to filtering
      // the last-known full customer list client-side instead of surfacing
      // a hard failure — a delegate mid-sale can still find an existing
      // customer by name/phone even with no signal. Only truly out of
      // options (nothing ever cached) does this rethrow.
      final cached = getCachedCustomerList();
      if (cached.isEmpty) rethrow;
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return cached;
      return cached
          .where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q))
          .toList();
    }
  }

  @override
  List<ClientModel> getCachedCustomerList() {
    final list = _cache.get(_kCustomerList) as List?;
    if (list == null) return [];
    try {
      return list.map((e) => ClientModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

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
  Future<List<SellableProductModel>> getSellableProducts({int? customerId}) async {
    final products = await _remote.fetchSellableProducts(customerId: customerId);
    await _cache.set(_kSellableProducts, products.map((p) => p.toJson()).toList());
    return products;
  }

  @override
  List<SellableProductModel> getCachedSellableProducts() {
    final list = _cache.get(_kSellableProducts) as List?;
    if (list == null) return [];
    try {
      return list.map((e) => SellableProductModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

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
    double discountAmount = 0,
    double? latitude,
    double? longitude,
  }) =>
      _remote.submitInvoice(
        clientId: clientId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: cashReceived,
        discountAmount: discountAmount,
        latitude: latitude,
        longitude: longitude,
      );

  @override
  Future<List<DelegateInvoiceModel>> getInvoices() => _remote.fetchInvoices();

  @override
  Future<DelegateInvoiceModel> updateInvoice({
    required int invoiceId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double discountAmount = 0,
  }) =>
      _remote.updateInvoice(
        invoiceId: invoiceId,
        salesItems: salesItems,
        returnedItems: returnedItems,
        cashReceived: cashReceived,
        discountAmount: discountAmount,
      );

  @override
  Future<CustomerInvoiceHistoryModel> getCustomerInvoiceHistory(int customerId, {int page = 1}) =>
      _remote.fetchCustomerInvoiceHistory(customerId, page: page);

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
  Future<String> deleteExpenseRecord(int id) => _remote.deleteExpenseRecord(id);

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
  Future<String> deleteCustomerCollectionRecord(int id) => _remote.deleteCustomerCollectionRecord(id);

  @override
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo}) =>
      _remote.fetchReportByRegion(period: period, dateFrom: dateFrom, dateTo: dateTo);

  @override
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo}) =>
      _remote.fetchReportByProduct(period: period, dateFrom: dateFrom, dateTo: dateTo);
}
