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
    } catch (e) {
      emit(AuthFailure(_msg(e)));
    }
  }

  Future<void> _onLogout(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _repo.logout();
    emit(AuthUnauthenticated());
  }

  String _msg(Object e) {
    if (e is DioException) {
      // Wrong-credentials (422) responses carry BOTH a generic top-level
      // message ("بيانات غير صالحة.") and the specific one in errors.email —
      // the field-specific message must win, or the user only ever sees the
      // generic one. The inactive-account response (403) has no errors key
      // at all, so it falls through to the top-level message correctly.
      final data = e.response?.data;
      final fieldMsg = data?['errors']?['email']?[0] as String?;
      final topMsg = data?['message'] as String?;
      return fieldMsg ?? topMsg ?? 'فشل الاتصال بالخادم.';
    }
    return 'حدث خطأ غير متوقع: $e';
  }
}
