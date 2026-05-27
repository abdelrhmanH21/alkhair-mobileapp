import 'package:get_it/get_it.dart';

import '../network/api_client.dart';
import '../utils/secure_session.dart';
import '../utils/gps_service.dart';
import '../utils/bluetooth_printer.dart';

import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

import '../../features/delegate/data/datasources/delegate_remote_datasource.dart';
import '../../features/delegate/data/repositories/delegate_repository_impl.dart';
import '../../features/delegate/domain/repositories/delegate_repository.dart';
import '../../features/delegate/presentation/bloc/delegate_bloc.dart';

import '../../features/admin/data/datasources/admin_remote_datasource.dart';
import '../../features/admin/presentation/bloc/admin_bloc.dart';

final sl = GetIt.instance;

void setupServiceLocator() {
  // ── Core ────────────────────────────────────────────────────────────────────
  sl.registerLazySingleton<SecureSession>(() => SecureSession());
  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<GpsService>(() => GpsService());
  sl.registerLazySingleton<BluetoothPrinterService>(() => BluetoothPrinterService());

  // ── Auth feature ─────────────────────────────────────────────────────────
  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl(sl()));
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(sl(), sl()));
  sl.registerLazySingleton<LoginUseCase>(() => LoginUseCase(sl()));
  sl.registerFactory<AuthBloc>(() => AuthBloc(sl(), sl()));

  // ── Delegate feature ─────────────────────────────────────────────────────
  sl.registerLazySingleton<DelegateRemoteDataSource>(() => DelegateRemoteDataSourceImpl(sl()));
  sl.registerLazySingleton<DelegateRepository>(() => DelegateRepositoryImpl(sl()));
  sl.registerFactory<DelegateBloc>(() => DelegateBloc(sl(), sl()));

  // ── Admin feature ────────────────────────────────────────────────────────
  sl.registerLazySingleton<AdminRemoteDataSource>(() => AdminRemoteDataSourceImpl(sl()));
  sl.registerFactory<AdminBloc>(() => AdminBloc(sl()));
}
