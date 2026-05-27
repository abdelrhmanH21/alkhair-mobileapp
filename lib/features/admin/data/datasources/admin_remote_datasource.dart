import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/admin_models.dart';

abstract class AdminRemoteDataSource {
  Future<DashboardStatsModel> fetchDashboard();
  Future<List<DelegateModel>> fetchDelegates();
  Future<ShiftSummaryModel> fetchShiftSummary(int delegateId);
  Future<Map<String, dynamic>> settleDelegate({
    required int delegateId,
    required int treasuryId,
    required double physicalCash,
    String? notes,
  });
  Future<List<SimpleProductModel>> fetchProducts();
  Future<List<SimpleWarehouseModel>> fetchWarehouses();
  Future<void> createLoading({
    required int delegateId,
    required int warehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
  });
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final ApiClient _client;
  AdminRemoteDataSourceImpl(this._client);

  @override
  Future<DashboardStatsModel> fetchDashboard() async {
    final res = await _client.dio.get(ApiEndpoints.adminDashboard);
    return DashboardStatsModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<List<DelegateModel>> fetchDelegates() async {
    final res = await _client.dio.get(ApiEndpoints.adminDelegates);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => DelegateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ShiftSummaryModel> fetchShiftSummary(int delegateId) async {
    final res = await _client.dio.get(
      ApiEndpoints.adminShiftSummary,
      queryParameters: {'delegate_id': delegateId},
    );
    return ShiftSummaryModel.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<Map<String, dynamic>> settleDelegate({
    required int delegateId,
    required int treasuryId,
    required double physicalCash,
    String? notes,
  }) async {
    final res = await _client.dio.post(ApiEndpoints.adminSettle, data: {
      'delegate_id': delegateId,
      'treasury_id': treasuryId,
      'physical_cash': physicalCash,
      if (notes != null) 'notes': notes,
    });
    return res.data as Map<String, dynamic>;
  }

  @override
  Future<List<SimpleProductModel>> fetchProducts() async {
    final res = await _client.dio.get(ApiEndpoints.adminProducts);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => SimpleProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<SimpleWarehouseModel>> fetchWarehouses() async {
    final res = await _client.dio.get(ApiEndpoints.adminWarehouses);
    final list = res.data['data'] as List? ?? [];
    return list
        .map((e) => SimpleWarehouseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createLoading({
    required int delegateId,
    required int warehouseId,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    await _client.dio.post(ApiEndpoints.adminLoadings, data: {
      'delegate_id': delegateId,
      'warehouse_id': warehouseId,
      'items': items,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }
}
