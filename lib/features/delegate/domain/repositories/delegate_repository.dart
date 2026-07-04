import '../../data/models/loading_model.dart';
import '../../data/models/client_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/dashboard_model.dart';
import '../../data/models/sellable_product_model.dart';
import '../../data/models/catalog_product_model.dart';
import '../../data/models/customer_region_model.dart';

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
    double? latitude,
    double? longitude,
  });
  Future<List<DelegateInvoiceModel>> getInvoices();
  Future<LoadingModel> updateLoadingStatus(int id, String status);
}
