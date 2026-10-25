import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/utils/location_service.dart';
import '../../../../core/utils/pending_action_queue.dart';
import '../../data/models/client_model.dart';
import '../../data/models/customer_location_result.dart';

enum CaptureStatus {
  idle,
  checking,
  locating,
  sending,
  weakAccuracy,
  success,
  notApplied,
  savedOffline,
  servicesOff,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  error,
}

/// The تسجيل موقع عميل state machine behind the ONE "تسجيل الموقع" button:
/// permission check → GPS capture ([captureBestFix]) → send, or queue
/// through the existing offline queue (PendingActionType.customerLocation)
/// when there is no connection. Kept free of widgets so every branch is
/// unit-testable with a fake [LocationService].
class CustomerLocationController extends ChangeNotifier {
  final LocationService _location;
  final Future<CustomerLocationResult> Function(int customerId, LocationFix fix) _send;
  final bool Function() _isOnline;
  final Future<void> Function(PendingAction action) _enqueue;
  final CapturePolicy policy;

  CustomerLocationController({
    required LocationService location,
    required Future<CustomerLocationResult> Function(int customerId, LocationFix fix) send,
    required bool Function() isOnline,
    required Future<void> Function(PendingAction action) enqueue,
    this.policy = const CapturePolicy(),
  })  : _location = location,
        _send = send,
        _isOnline = isOnline,
        _enqueue = enqueue;

  /// For the panel's "تفعيل الموقع" / "فتح الإعدادات" buttons.
  LocationService get locationService => _location;

  CaptureStatus _status = CaptureStatus.idle;
  CaptureStatus get status => _status;

  /// Best fix of the last capture — kept for "حفظ رغم ذلك" after a weak fix.
  LocationFix? _fix;
  LocationFix? get fix => _fix;

  String? _message;
  String? get message => _message;

  CustomerLocationResult? _result;
  CustomerLocationResult? get result => _result;

  bool get busy =>
      _status == CaptureStatus.checking || _status == CaptureStatus.locating || _status == CaptureStatus.sending;

  void _set(CaptureStatus s, {String? message}) {
    _status = s;
    _message = message;
    notifyListeners();
  }

  /// Back to a clean slate (a different customer was selected).
  void reset() {
    _fix = null;
    _result = null;
    _set(CaptureStatus.idle);
  }

  /// The whole tap: confirm replacement (if the customer already has a
  /// pin) → permission → capture → send/queue. [confirmReplace] receives
  /// the previous record date and returns false to abort.
  Future<void> capture(
    ClientModel client, {
    required Future<bool> Function(DateTime? previousRecordedAt) confirmReplace,
  }) async {
    if (busy) return;
    if (client.hasLocation && !await confirmReplace(client.locationRecordedAt)) return;

    _fix = null;
    _result = null;
    _set(CaptureStatus.checking);

    try {
      if (!await _location.isServiceEnabled()) return _set(CaptureStatus.servicesOff);

      var perm = await _location.checkPermission();
      if (perm == LocationPermissionState.denied) perm = await _location.requestPermission();
      if (perm == LocationPermissionState.denied) return _set(CaptureStatus.permissionDenied);
      if (perm == LocationPermissionState.deniedForever) return _set(CaptureStatus.permissionDeniedForever);

      _set(CaptureStatus.locating);
      final fix = await captureBestFix(_location, policy: policy);
      _fix = fix;
      if (fix.accuracyM > policy.weakAboveM) return _set(CaptureStatus.weakAccuracy);
    } on LocationTimeoutException {
      return _set(CaptureStatus.timeout);
    } catch (_) {
      return _set(CaptureStatus.error, message: 'تعذر تحديد الموقع. حاول مرة أخرى.');
    }

    await _deliver(client);
  }

  /// "حفظ رغم ذلك" after a weak-accuracy fix.
  Future<void> saveAnyway(ClientModel client) async {
    if (_fix == null || busy) return;
    await _deliver(client);
  }

  Future<void> _deliver(ClientModel client) async {
    final fix = _fix!;
    if (!_isOnline()) return _queue(client, fix);

    _set(CaptureStatus.sending);
    try {
      final result = await _send(client.id, fix);
      _result = result;
      _set(result.applied ? CaptureStatus.success : CaptureStatus.notApplied);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null && code >= 400 && code < 500 && code != 408 && code != 429) {
        // The server looked at it and refused (validation, permission, …).
        final serverMessage = e.response?.data is Map ? e.response?.data['message'] as String? : null;
        return _set(CaptureStatus.error, message: serverMessage ?? 'تعذر حفظ الموقع.');
      }
      // No answer / timeout / 5xx / throttled: the fix is already captured —
      // keep it in the offline queue instead of making the delegate redo it.
      await _queue(client, fix);
    } catch (_) {
      await _queue(client, fix);
    }
  }

  Future<void> _queue(ClientModel client, LocationFix fix) async {
    await _enqueue(PendingAction(
      idempotencyKey: generateIdempotencyKey(),
      type: PendingActionType.customerLocation,
      payload: customerLocationPayload(client, fix),
      createdAt: DateTime.now(),
    ));
    _set(CaptureStatus.savedOffline);
  }
}

/// The queued payload — read back by DelegateSyncEngine._syncCustomerLocation
/// and summarized by SyncStatusPage. captured_at is the fix time, so a late
/// replay can never overwrite a newer pin (server last-write-wins).
Map<String, dynamic> customerLocationPayload(ClientModel client, LocationFix fix) => {
      'customer_id': client.id,
      'customer_name': client.name,
      'latitude': fix.latitude,
      'longitude': fix.longitude,
      'accuracy_m': double.parse(fix.accuracyM.toStringAsFixed(2)),
      'captured_at': fix.capturedAt.toUtc().toIso8601String(),
    };
