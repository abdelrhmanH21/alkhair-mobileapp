import '../../domain/repositories/app_config_repository.dart';
import '../datasources/app_config_remote_datasource.dart';
import '../models/app_config_model.dart';

class AppConfigRepositoryImpl implements AppConfigRepository {
  final AppConfigRemoteDataSource _dataSource;
  AppConfigRepositoryImpl(this._dataSource);

  @override
  Future<AppConfigModel> fetchSettings() => _dataSource.fetchSettings();
}
