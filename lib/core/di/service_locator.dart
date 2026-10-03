import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../utils/secure_session.dart';
import '../utils/gps_service.dart';
import '../utils/bluetooth_printer.dart';
import '../utils/push_notification_service.dart';
import '../utils/offline_cache_service.dart';
import '../utils/connectivity_service.dart';
import '../utils/pending_action_queue.dart';

import '../../features/app_config/data/datasources/app_config_local_datasource.dart';
import '../../features/app_config/data/datasources/app_config_remote_datasource.dart';
import '../../features/app_config/data/repositories/app_config_repository_impl.dart';
import '../../features/app_config/domain/repositories/app_config_repository.dart';
import '../../features/app_config/presentation/bloc/app_config_bloc.dart';

import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

import '../../features/delegate/data/datasources/delegate_remote_datasource.dart';
import '../../features/delegate/data/repositories/delegate_repository_impl.dart';
import '../../features/delegate/data/sync/delegate_sync_engine.dart';
import '../../features/delegate/domain/repositories/delegate_repository.dart';
import '../../features/delegate/presentation/bloc/delegate_bloc.dart';

import '../../features/admin/data/datasources/admin_remote_datasource.dart';
import '../../features/admin/presentation/bloc/admin_bloc.dart';

final sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  // ── Core ────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<SecureSession>(() => SecureSession());
  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<GpsService>(() => GpsService());
  sl.registerLazySingleton<BluetoothPrinterService>(() => BluetoothPrinterService());
  sl.registerLazySingleton<PushNotificationService>(() => PushNotificationService(sl()));

  final prefs = await SharedPreferences.getInstance();
  sl.registerLazySingleton<OfflineCacheService>(() => OfflineCacheService(prefs));

  final connectivity = ConnectivityService();
  await connectivity.initialize();
  sl.registerLazySingleton<ConnectivityService>(() => connectivity);

  sl.registerLazySingleton<PendingActionQueue>(() => PendingActionQueue(sl()));

  // ── AppConfig feature ────────────────────────────────────────────────────
  sl.registerLazySingleton<AppConfigLocalDataSource>(() => AppConfigLocalDataSource(prefs));
  sl.registerLazySingleton<AppConfigRemoteDataSource>(() => AppConfigRemoteDataSourceImpl(sl()));
  sl.registerLazySingleton<AppConfigRepository>(() => AppConfigRepositoryImpl(sl(), sl()));
  sl.registerFactory<AppConfigBloc>(() => AppConfigBloc(sl()));

  // ── Auth feature ─────────────────────────────────────────────────────────
  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl(sl()));
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(sl(), sl()));
  sl.registerLazySingleton<LoginUseCase>(() => LoginUseCase(sl()));
  sl.registerFactory<AuthBloc>(() => AuthBloc(sl(), sl(), sl()));

  // ── Delegate feature ─────────────────────────────────────────────────────
  sl.registerLazySingleton<DelegateRemoteDataSource>(() => DelegateRemoteDataSourceImpl(sl()));
  sl.registerLazySingleton<DelegateRepository>(() => DelegateRepositoryImpl(sl(), sl()));
  sl.registerFactory<DelegateBloc>(() => DelegateBloc(sl(), sl()));
  sl.registerLazySingleton<DelegateSyncEngine>(() => DelegateSyncEngine(sl(), sl(), sl()));

  // ── Admin feature ────────────────────────────────────────────────────────
  sl.registerLazySingleton<AdminRemoteDataSource>(() => AdminRemoteDataSourceImpl(sl()));
  sl.registerFactory<AdminBloc>(() => AdminBloc(sl()));
}
