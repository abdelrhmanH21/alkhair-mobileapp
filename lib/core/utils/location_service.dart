import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// One GPS fix as the تسجيل موقع عميل flow sees it. [capturedAt] is the
/// phone's clock at the moment of the fix — sent as captured_at so the
/// server's last-write-wins compares capture times, not sync times.
class LocationFix {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final DateTime capturedAt;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.capturedAt,
  });
}

enum LocationPermissionState { granted, denied, deniedForever }

/// Thin seam over geolocator so the capture flow can be tested with a fake.
/// Nothing here runs in the background: [fixes] is only listened to for the
/// few seconds of one explicit "تسجيل الموقع" tap, then cancelled.
abstract class LocationService {
  Future<bool> isServiceEnabled();
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();

  /// High-accuracy fixes, as fast as the device produces them, until the
  /// subscription is cancelled.
  Stream<LocationFix> fixes();

  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionState> checkPermission() async => _map(await Geolocator.checkPermission());

  @override
  Future<LocationPermissionState> requestPermission() async => _map(await Geolocator.requestPermission());

  @override
  Stream<LocationFix> fixes() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0),
      ).map((p) => LocationFix(
            latitude: p.latitude,
            longitude: p.longitude,
            accuracyM: p.accuracy,
            capturedAt: DateTime.now(),
          ));

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  static LocationPermissionState _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }
}

/// Timing/accuracy policy for one capture (see [captureBestFix]).
class CapturePolicy {
  /// How long to wait for the FIRST fix before giving up (timeout state).
  final Duration firstFixTimeout;

  /// Extra time spent refining when the first fix is worse than [refineAboveM].
  final Duration refineWindow;
  final double refineAboveM;

  /// A fix at or under this accuracy is used immediately.
  final double goodEnoughM;

  /// Best accuracy worse than this → "الدقة ضعيفة" (retry / save anyway).
  final double weakAboveM;

  const CapturePolicy({
    this.firstFixTimeout = const Duration(seconds: 12),
    this.refineWindow = const Duration(seconds: 8),
    this.refineAboveM = 75,
    this.goodEnoughM = 30,
    this.weakAboveM = 100,
  });
}

class LocationTimeoutException implements Exception {
  const LocationTimeoutException();
}

/// Listens to [service.fixes] for at most firstFixTimeout + refineWindow
/// and returns the most accurate fix:
///  - first fix ≤ goodEnoughM → returned at once;
///  - first fix ≤ refineAboveM → returned at once (good enough, fast);
///  - otherwise keep listening up to refineWindow, stopping early as soon as
///    a fix ≤ goodEnoughM arrives, and return the best one seen.
/// Throws [LocationTimeoutException] if no fix arrives in firstFixTimeout.
/// The subscription is always cancelled before returning.
Future<LocationFix> captureBestFix(LocationService service, {CapturePolicy policy = const CapturePolicy()}) {
  final done = Completer<LocationFix>();
  LocationFix? best;
  Timer? firstTimer;
  Timer? refineTimer;
  late final StreamSubscription<LocationFix> sub;

  void finish([Object? error]) {
    if (done.isCompleted) return;
    firstTimer?.cancel();
    refineTimer?.cancel();
    unawaited(sub.cancel());
    if (error != null) {
      done.completeError(error);
    } else {
      done.complete(best!);
    }
  }

  sub = service.fixes().listen(
    (fix) {
      if (best == null || fix.accuracyM < best!.accuracyM) best = fix;
      if (best!.accuracyM <= policy.goodEnoughM) return finish();
      if (refineTimer == null) {
        // First fix just arrived.
        firstTimer?.cancel();
        if (best!.accuracyM <= policy.refineAboveM) return finish();
        refineTimer = Timer(policy.refineWindow, finish);
      }
    },
    onError: (Object e) {
      // A transient stream error after a fix keeps the best fix so far.
      if (best != null) return finish();
      finish(e);
    },
    onDone: () => best != null ? finish() : finish(const LocationTimeoutException()),
  );
  firstTimer = Timer(policy.firstFixTimeout, () {
    if (best == null) finish(const LocationTimeoutException());
  });

  return done.future;
}
