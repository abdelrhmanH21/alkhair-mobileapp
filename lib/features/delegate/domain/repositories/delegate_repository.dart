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
  });
  Future<List<DelegateInvoiceModel>> getInvoices();
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
  });
  Future<String> submitCustomerCollection({
    required int customerId,
    required double amount,
    required String paymentMethod,
    String? notes,
  });
  Future<List<ExpenseRecordModel>> getExpenseRecords();
  Future<ExpenseRecordModel> updateExpenseRecord({
    required int id,
    required double amount,
    required String description,
  });
  Future<List<CustomerCollectionRecordModel>> getCustomerCollectionRecords();
  Future<CustomerCollectionRecordModel> updateCustomerCollectionRecord({
    required int id,
    required double amount,
    String? notes,
  });
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo});
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo});
}
