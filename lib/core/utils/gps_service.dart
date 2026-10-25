import 'package:geolocator/geolocator.dart';

class GpsService {
  /// Best-effort GPS capture: never blocks the caller.
  ///
  /// Returns coordinates quickly using cached position if fresh (< 60 s).
  /// Falls back to a timeout-bounded live request. Returns null on any error
  /// so the invoice flow is never halted.
  Future<({double? lat, double? lng})> captureCoordinates() async {
    try {
      final permission = await _ensurePermission();
      if (!permission) return (lat: null, lng: null);

      // Try last known position first (fast; works even while moving)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final age = DateTime.now().difference(last.timestamp);
        if (age.inSeconds < 60) {
          return (lat: last.latitude, lng: last.longitude);
        }
      }

      // Request a fresh fix with a short timeout so the UI is never blocked
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  /// Check only — never prompts. The location permission is now declared
  /// for every Android version (and iOS) for تسجيل موقع عميل, which is
  /// where the delegate grants it; asking here would pop a system dialog in
  /// the middle of a sale. Location services off → skip at once instead of
  /// waiting out the fix timeout.
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }
}
