import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Generic disk cache for "last known good" server responses (product
/// lists, customer list, dashboard summary, current loading, ...), so a
/// screen can show *something* real immediately when opened offline instead
/// of a blank/error screen — see [AppConfigLocalDataSource] for the original
/// version of this pattern (logo/company-name caching), generalized here so
/// every delegate read-screen can reuse the same store instead of each
/// hand-rolling its own SharedPreferences key.
///
/// Uses shared_preferences (already a dependency, already used for exactly
/// this purpose by AppConfig) rather than sqflite: every cached value here is
/// a whole-response JSON blob (a list or a map) read back in full, never
/// queried/filtered on-disk — there's no relational access pattern that
/// would benefit from a real database, so the extra native dependency isn't
/// justified for Phase 1's "last-known snapshot" scope.
class OfflineCacheService {
  static const _prefix = 'offline_cache_';
  final SharedPreferences _prefs;

  OfflineCacheService(this._prefs);

  Future<void> set(String key, dynamic jsonValue) =>
      _prefs.setString('$_prefix$key', jsonEncode(jsonValue));

  /// Returns the decoded JSON (a `Map` or a `List`, mirroring whatever was
  /// passed to [set]) previously cached under [key], or null if nothing was
  /// ever cached (or it was corrupt/unreadable).
  dynamic get(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String key) => _prefs.remove('$_prefix$key');
}
