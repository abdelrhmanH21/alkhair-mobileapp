import '../../../../core/utils/secure_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remote;
  final SecureSession _session;

  AuthRepositoryImpl(this._remote, this._session);

  @override
  Future<AuthResponseModel> login({
    required String email,
    required String password,
  }) async {
    final result = await _remote.login(email: email, password: password);
    // Persist token through the session wrapper
    await _session.write(result.token);
    return result;
  }

  @override
  Future<void> logout() async {
    await _remote.logout();
    await _session.clear();
  }

  @override
  Future<UserModel?> restoreSession() async {
    final token = await _session.read();
    if (token == null) return null;
    try {
      return await _remote.me();
    } catch (_) {
      await _session.clear();
      return null;
    }
  }
}
