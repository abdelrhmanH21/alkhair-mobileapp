import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';

import 'features/app_config/presentation/bloc/app_config_bloc.dart';
import 'features/app_config/presentation/bloc/app_config_event.dart';

import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'features/auth/presentation/pages/login_page.dart';

import 'features/delegate/presentation/bloc/delegate_bloc.dart';
import 'features/delegate/presentation/pages/delegate_home_page.dart';

import 'features/admin/presentation/bloc/admin_bloc.dart';
import 'features/admin/presentation/pages/admin_dashboard_page.dart';

class AlKhairApp extends StatelessWidget {
  const AlKhairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AppConfigBloc>(
          create: (_) => sl<AppConfigBloc>()..add(AppConfigFetchRequested()),
        ),
        BlocProvider<AuthBloc>(
          create: (_) => sl<AuthBloc>()..add(AuthSessionRestoreRequested()),
        ),
        BlocProvider<DelegateBloc>(create: (_) => sl<DelegateBloc>()),
        BlocProvider<AdminBloc>(create: (_) => sl<AdminBloc>()),
      ],
      child: MaterialApp(
        title: 'الخير للألبان',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        // Full Arabic RTL support
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [
          Locale('ar', 'SA'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (ctx, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _RootNavigator(),
      ),
    );
  }
}

class _RootNavigator extends StatelessWidget {
  const _RootNavigator();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (_, state) {
        if (state is AuthLoading || state is AuthInitial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (state is AuthAuthenticated) {
          return _routeForRole(state);
        }
        return const LoginPage();
      },
    );
  }

  Widget _routeForRole(AuthAuthenticated state) {
    if (state.user.isAdmin) {
      return const AdminDashboardPage();
    }
    if (state.user.isDelegate) {
      // Delegate lands on the home dashboard, which always shows performance
      // stats plus a non-blocking shipment-status card; the loading /
      // sell / truck-stock / invoice workflows are reached from there.
      return const DelegateHomePage();
    }
    // Unsupported role — show login with message
    return const LoginPage();
  }
}
