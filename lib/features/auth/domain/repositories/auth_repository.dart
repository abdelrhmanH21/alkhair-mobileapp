import '../../data/models/user_model.dart';

abstract class AuthRepository {
  Future<AuthResponseModel> login({required String email, required String password});
  Future<void> logout();
  Future<UserModel?> restoreSession();
}
