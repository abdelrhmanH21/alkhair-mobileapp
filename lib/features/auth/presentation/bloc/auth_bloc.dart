import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _login;
  final AuthRepository _repo;

  AuthBloc(this._login, this._repo) : super(AuthInitial()) {
    on<AuthSessionRestoreRequested>(_onRestoreSession);
    on<AuthLoginRequested>(_onLogin);
    on<AuthLogoutRequested>(_onLogout);
  }

  Future<void> _onRestoreSession(
    AuthSessionRestoreRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _repo.restoreSession();
      if (user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLogin(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final result = await _login(email: event.email, password: event.password);
      emit(AuthAuthenticated(result.user));
    } on DioException catch (e) {
      final msg = e.response?.data?['message'] as String? ??
          e.response?.data?['errors']?['email']?[0] as String? ??
          'فشل الاتصال بالخادم.';
      emit(AuthFailure(msg));
    } catch (e) {
      emit(AuthFailure('حدث خطأ غير متوقع.'));
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _repo.logout();
    emit(AuthUnauthenticated());
  }
}
