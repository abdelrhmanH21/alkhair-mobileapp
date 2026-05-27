import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/app_config_repository.dart';
import 'app_config_event.dart';
import 'app_config_state.dart';

class AppConfigBloc extends Bloc<AppConfigEvent, AppConfigState> {
  final AppConfigRepository _repository;

  AppConfigBloc(this._repository) : super(AppConfigInitial()) {
    on<AppConfigFetchRequested>(_onFetch);
  }

  Future<void> _onFetch(
    AppConfigFetchRequested event,
    Emitter<AppConfigState> emit,
  ) async {
    try {
      final config = await _repository.fetchSettings();
      emit(AppConfigLoaded(config));
    } catch (_) {
      emit(AppConfigLoadFailed());
    }
  }
}
