import '../../data/models/user_model.dart';
import '../repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository _repo;
  LoginUseCase(this._repo);

  Future<AuthResponseModel> call({
    required String email,
    required String password,
  }) =>
      _repo.login(email: email, password: password);
}
