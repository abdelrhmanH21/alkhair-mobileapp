import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

/// What one device-authentication attempt came back as.
enum DeviceAuthOutcome {
  /// Biometric OR device PIN/pattern/passcode matched.
  success,

  /// Prompt completed but credentials did not match.
  failed,

  /// User dismissed the prompt (or the system cancelled it).
  canceled,

  /// Too many wrong attempts — the device itself is refusing for now.
  lockedOut,

  /// The device has no screen lock / biometric at all, so there is nothing
  /// to authenticate against.
  unavailable,

  /// Anything else (plugin/device error).
  error,
}

/// Seam over `local_auth` so the reveal logic can be tested without hardware.
abstract class DeviceAuthenticator {
  Future<DeviceAuthOutcome> authenticate(String reason);
}

/// Real implementation. `biometricOnly: false` is what gives the built-in
/// fallback: Face ID / fingerprint first, and the device's own PIN / pattern /
/// passcode when biometrics are missing, un-enrolled, or locked out — no
/// custom PIN system.
class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  final LocalAuthentication _auth;
  LocalAuthDeviceAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  @override
  Future<DeviceAuthOutcome> authenticate(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) return DeviceAuthOutcome.unavailable;
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceAuthOutcome.success : DeviceAuthOutcome.failed;
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.userRequestedFallback:
          return DeviceAuthOutcome.canceled;
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return DeviceAuthOutcome.lockedOut;
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
          return DeviceAuthOutcome.unavailable;
        default:
          return DeviceAuthOutcome.error;
      }
    } catch (_) {
      return DeviceAuthOutcome.error;
    }
  }
}

/// What the UI should tell the user after a reveal attempt.
enum RevealResult {
  /// Authenticated — figures are visible.
  revealed,

  /// Device has no screen lock at all, so there was nothing to authenticate
  /// against: figures are shown anyway (never permanently blocked from the
  /// delegate's own legitimate data) and the UI must say so clearly.
  revealedUnprotected,

  /// Wrong credentials — stays masked.
  denied,

  /// User backed out — stays masked, no message needed.
  canceled,

  /// Device refused for now (too many attempts) — stays masked.
  lockedOut,

  /// Unexpected failure — stays masked, retry possible.
  error,

  /// A prompt was already open or the data was already visible.
  ignored,
}

/// Session-scoped lock for the free-pricing delegate's money figures
/// ("المستحق لك" on the dashboard, the per-loading/per-sale variance amounts
/// on the detail page). ONE shared instance (see service_locator.dart), so
/// authenticating once unlocks both screens together.
///
/// Re-lock rules:
///  * [revealDuration] (60s) after a successful authentication — fixed, not
///    sliding, so leaving the phone open on this screen can't keep it
///    revealed indefinitely;
///  * the app going to the background (paused/hidden) — but never while the
///    auth prompt itself is open, since the system prompt can trigger
///    lifecycle changes;
///  * the dashboard section being disposed (logout, leaving the delegate
///    home) via [lock].
class SensitiveRevealController extends ChangeNotifier with WidgetsBindingObserver {
  final DeviceAuthenticator _authenticator;
  final Duration revealDuration;

  SensitiveRevealController(
    this._authenticator, {
    this.revealDuration = const Duration(seconds: 60),
  });

  bool _revealed = false;
  bool _authenticating = false;
  Timer? _timer;

  bool get isRevealed => _revealed;
  bool get isAuthenticating => _authenticating;

  /// Starts listening for app-backgrounding. Kept out of the constructor so
  /// unit tests don't need a Widgets binding.
  void bindToAppLifecycle() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      lock();
    }
  }

  Future<RevealResult> requestReveal({String reason = 'أكّد هويتك لعرض مستحقاتك'}) async {
    if (_revealed || _authenticating) return RevealResult.ignored;

    _authenticating = true;
    notifyListeners();
    final DeviceAuthOutcome outcome;
    try {
      outcome = await _authenticator.authenticate(reason);
    } finally {
      _authenticating = false;
    }

    switch (outcome) {
      case DeviceAuthOutcome.success:
        _reveal();
        return RevealResult.revealed;
      case DeviceAuthOutcome.unavailable:
        _reveal();
        return RevealResult.revealedUnprotected;
      case DeviceAuthOutcome.failed:
        notifyListeners();
        return RevealResult.denied;
      case DeviceAuthOutcome.canceled:
        notifyListeners();
        return RevealResult.canceled;
      case DeviceAuthOutcome.lockedOut:
        notifyListeners();
        return RevealResult.lockedOut;
      case DeviceAuthOutcome.error:
        notifyListeners();
        return RevealResult.error;
    }
  }

  void _reveal() {
    _revealed = true;
    _timer?.cancel();
    _timer = Timer(revealDuration, lock);
    notifyListeners();
  }

  /// Re-masks immediately (manual lock button, backgrounding, timeout,
  /// logout/dispose). No-op when already locked.
  void lock() {
    _timer?.cancel();
    _timer = null;
    if (!_revealed) return;
    _revealed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
