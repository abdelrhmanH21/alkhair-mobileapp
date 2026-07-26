import '../../domain/repositories/app_config_repository.dart';
import '../datasources/app_config_local_datasource.dart';
import '../datasources/app_config_remote_datasource.dart';
import '../models/app_config_model.dart';

class AppConfigRepositoryImpl implements AppConfigRepository {
  final AppConfigRemoteDataSource _dataSource;
  final AppConfigLocalDataSource _localDataSource;
  AppConfigRepositoryImpl(this._dataSource, this._localDataSource);

  @override
  Future<AppConfigModel> fetchSettings() async {
    final config = await _dataSource.fetchSettings();
    // Write-through so the NEXT cold launch's getCachedSettings() reflects
    // this fetch, even if this session never calls it again.
    await _localDataSource.save(config.toJson());
    return config;
  }

  @override
  AppConfigModel? getCachedSettings() => _localDataSource.read();
}
