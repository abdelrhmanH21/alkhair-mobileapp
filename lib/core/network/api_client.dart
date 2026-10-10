import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/number_input.dart';
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
    _dio.interceptors.add(DigitNormalizingInterceptor());
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

/// Last pass before anything leaves the app: numeric values typed (or pasted,
/// or queued offline) with Arabic-Indic/Persian digits go out as Latin, and
/// query parameters (every search box) get Latin digits. Free text is never
/// rewritten — see normalizeNumericPayload().
class DigitNormalizingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    if (data is FormData) {
      for (var i = 0; i < data.fields.length; i++) {
        final field = data.fields[i];
        final normalized = normalizeNumericPayload(field.value, field.key) as String;
        if (normalized != field.value) data.fields[i] = MapEntry(field.key, normalized);
      }
    } else if (data is Map || data is List) {
      options.data = normalizeNumericPayload(data);
    }
    if (options.queryParameters.isNotEmpty) {
      options.queryParameters = options.queryParameters
          .map((k, v) => MapEntry(k, v is String ? normalizeDigits(v) : v));
    }
    handler.next(options);
  }
}
