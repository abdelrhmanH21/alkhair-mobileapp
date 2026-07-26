import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/app_config_model.dart';
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

  /// Returns the loaded config, retrying the fetch first if it never
  /// succeeded. [app.dart] only dispatches [AppConfigFetchRequested] once,
  /// at app startup — a single network hiccup at that moment (very real for
  /// a delegate opening the app in the field on patchy mobile data) leaves
  /// this bloc stuck in [AppConfigLoadFailed] (or still [AppConfigInitial])
  /// for the rest of the session, since nothing else ever re-dispatches the
  /// event. That silently drops the receipt logo/company name/header text
  /// (all sourced from this config) from every print for the entire
  /// session, with no error ever shown — root cause of a real physical
  /// print missing its logo and starting straight at the invoice-number
  /// line. Callers that need the config for a receipt should await this
  /// instead of reading [state] directly.
  Future<AppConfigModel?> ensureLoaded() async {
    final current = state;
    if (current is AppConfigLoaded) return current.config;
    add(AppConfigFetchRequested());
    try {
      final result = await stream
          .firstWhere((s) => s is AppConfigLoaded || s is AppConfigLoadFailed)
          .timeout(const Duration(seconds: 10));
      return result is AppConfigLoaded ? result.config : null;
    } catch (_) {
      return null;
    }
  }
}
