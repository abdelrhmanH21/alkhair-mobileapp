import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Copies a picked photo into a persistent app-local directory so it
/// survives an app restart while queued offline — PendingActionQueue's
/// payload is JSON (via OfflineCacheService/SharedPreferences) and can only
/// hold a file PATH string, never raw bytes, and image_picker's own
/// original path may live in a transient OS-managed cache/temp directory
/// that isn't guaranteed to still exist by the time connectivity returns.
class PendingPhotoStorage {
  static Future<String> persist(File source, String idempotencyKey) async {
    final dir = await getApplicationSupportDirectory();
    final pendingDir = Directory('${dir.path}/pending_photos');
    if (!await pendingDir.exists()) {
      await pendingDir.create(recursive: true);
    }
    final ext = source.path.split('.').last;
    final dest = File('${pendingDir.path}/$idempotencyKey.$ext');
    await source.copy(dest.path);
    return dest.path;
  }

  /// Called once a queued action has synced (or been permanently discarded)
  /// so this directory doesn't grow unbounded.
  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup — a leftover file here is harmless clutter,
      // never worth surfacing an error to the delegate over.
    }
  }
}
