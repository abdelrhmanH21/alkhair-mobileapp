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
import '../../data/models/customer_invoice_history_model.dart';

abstract class DelegateRepository {
  Future<LoadingModel?> getCurrentLoading();
  Future<LoadingModel> confirmLoading();
  Future<List<TruckStockModel>> getTruckStock();
  Future<DashboardModel> getDashboard();
  Future<List<ClientModel>> searchClients(String query);

  // ── Offline cache reads (synchronous, last-known snapshot) ───────────────
  // Let a screen show *something* real the instant it opens, before the
  // corresponding Future above has resolved — see OfflineCacheService.
  LoadingModel? getCachedLoading();
  List<TruckStockModel> getCachedTruckStock();
  DashboardModel? getCachedDashboard();
  List<SellableProductModel> getCachedSellableProducts();
  List<ClientModel> getCachedCustomerList();

  /// Optimistically applies a per-product stock delta (negative for a sale,
  /// positive for a 'سليم' return) directly to the cached truck-stock/
  /// sellable-products snapshots — used when an action is queued offline
  /// (see PendingActionQueue) so a SECOND queued sale for the same product,
  /// entered before connectivity returns, sees the reduced stock instead of
  /// the stale pre-deduction number. Superseded by real data the next time
  /// either fetch succeeds (including the sync engine's post-sync refresh).
  Future<void> applyOptimisticTruckStockDelta(Map<int, double> productIdToQtyDelta);
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    int? customerRegionId,
    double? initialBalance,
  });
  Future<List<SellableProductModel>> getSellableProducts({int? customerId});
  Future<List<CatalogProductModel>> getSalesCatalogProducts();
  Future<List<CustomerRegionModel>> getCustomerRegions();
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double discountAmount = 0,
    double? latitude,
    double? longitude,
    String? idempotencyKey,
  });
  Future<List<DelegateInvoiceModel>> getInvoices();
  Future<DelegateInvoiceModel> updateInvoice({
    required int invoiceId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double discountAmount = 0,
  });
  Future<CustomerInvoiceHistoryModel> getCustomerInvoiceHistory(int customerId, {int page = 1});
  Future<LoadingModel> updateLoadingStatus(int id, String status);
  Future<SettlementSummaryModel> getSettlementSummary();
  Future<void> submitSettlementRequest({
    required double cashAmount,
    required double walletAmount,
    String? notes,
  });
  Future<List<PenaltyModel>> getPenalties();
  Future<List<AdvanceModel>> getAdvances();
  Future<List<CommissionDayModel>> getCommissionBreakdown();
  Future<String> submitExpense({
    required double amount,
    required String description,
    int? categoryId,
    String? notes,
    String? idempotencyKey,
  });
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
    String? idempotencyKey,
  });
  Future<List<ExpenseRecordModel>> getExpenseRecords();
  Future<ExpenseRecordModel> updateExpenseRecord({
    required int id,
    required double amount,
    required String description,
  });
  Future<String> deleteExpenseRecord(int id);
  Future<List<CustomerCollectionRecordModel>> getCustomerCollectionRecords();
  Future<CustomerCollectionRecordModel> updateCustomerCollectionRecord({
    required int id,
    required double amount,
    String? notes,
  });
  Future<String> deleteCustomerCollectionRecord(int id);
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo});
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo});
}
