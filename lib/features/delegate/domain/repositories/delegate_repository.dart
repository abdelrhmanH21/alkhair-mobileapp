import '../../data/models/loading_model.dart';
import '../../data/models/client_model.dart';
import '../../data/models/invoice_model.dart';

abstract class DelegateRepository {
  Future<LoadingModel?> getCurrentLoading();
  Future<LoadingModel> confirmLoading();
  Future<List<TruckStockModel>> getTruckStock();
  Future<List<ClientModel>> searchClients(String query);
  Future<ClientModel> createClient({
    required String name,
    required String phone,
    String? region,
    double? initialBalance,
  });
  Future<DelegateInvoiceModel> submitInvoice({
    required int clientId,
    required List<Map<String, dynamic>> salesItems,
    required List<Map<String, dynamic>> returnedItems,
    required double cashReceived,
    double? latitude,
    double? longitude,
  });
  Future<List<DelegateInvoiceModel>> getInvoices();
}
