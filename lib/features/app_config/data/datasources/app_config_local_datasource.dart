import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config_model.dart';

/// Disk cache of the last successfully fetched [AppConfigModel] JSON, so a
/// cold app launch can show the last-known company logo/name immediately
/// (see [AppConfigBloc]'s cache-then-refresh fetch) instead of the login
/// screen sitting on a blank/default placeholder until a fresh network
/// round trip completes.
class AppConfigLocalDataSource {
  static const _key = 'cached_app_config_json';
  final SharedPreferences _prefs;

  AppConfigLocalDataSource(this._prefs);

  Future<void> save(Map<String, dynamic> json) => _prefs.setString(_key, jsonEncode(json));

  AppConfigModel? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AppConfigModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
