import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../models/app_config_model.dart';

abstract class AppConfigRemoteDataSource {
  Future<AppConfigModel> fetchSettings();
}

class AppConfigRemoteDataSourceImpl implements AppConfigRemoteDataSource {
  final ApiClient _client;
  AppConfigRemoteDataSourceImpl(this._client);

  @override
  Future<AppConfigModel> fetchSettings() async {
    final res = await _client.dio.get(ApiEndpoints.appSettings);
    return AppConfigModel.fromJson(res.data as Map<String, dynamic>);
  }
}
