import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps FlutterSecureStorage and wipes the token when the app fully detaches
/// from the OS (i.e., the operating application instance is closed).
class SecureSession with WidgetsBindingObserver {
  static const _tokenKey = 'mobile_auth_token';
  final FlutterSecureStorage _storage;

  SecureSession() : _storage = const FlutterSecureStorage() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _storage.delete(key: _tokenKey);
    }
  }

  Future<void> write(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> read() => _storage.read(key: _tokenKey);
  Future<void> clear() => _storage.delete(key: _tokenKey);

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
