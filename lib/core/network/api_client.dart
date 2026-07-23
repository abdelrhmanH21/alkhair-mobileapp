import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_endpoints.dart';

class ApiClient {
  static const _tokenKey = 'mobile_auth_token';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          baseUrl: ApiEndpoints.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        )) {
    _dio.interceptors.add(_AuthInterceptor(_storage, _tokenKey));
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }

  Dio get dio => _dio;

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> getToken() => _storage.read(key: _tokenKey);
}

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  final String _tokenKey;

  _AuthInterceptor(this._storage, this._tokenKey);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Bounded: this runs before Dio's own connect/receive timeouts start
    // ticking, so an unbounded read here (e.g. a secure-storage/Keystore
    // stall) would hang every request — including login — forever with no
    // timeout anywhere in the chain to catch it. Falling back to "no token"
    // on timeout just means the request goes out unauthenticated (a normal,
    // already-handled 401 path) instead of never going out at all.
    String? token;
    try {
      token = await _storage
          .read(key: _tokenKey)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      token = null;
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
