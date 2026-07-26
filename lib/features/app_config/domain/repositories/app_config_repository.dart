import '../../data/models/app_config_model.dart';

abstract class AppConfigRepository {
  Future<AppConfigModel> fetchSettings();

  /// Last successfully fetched config persisted to disk, or null if none
  /// has ever been cached (e.g. very first launch). Synchronous — backed by
  /// an already-initialized SharedPreferences instance — so a caller can use
  /// it to seed UI instantly without awaiting anything.
  AppConfigModel? getCachedSettings();
}
