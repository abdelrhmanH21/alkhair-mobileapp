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
}
