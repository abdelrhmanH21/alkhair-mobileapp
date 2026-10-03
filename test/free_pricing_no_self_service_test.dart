import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/push_notification_service.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';
import 'package:alkhair_mobileapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:alkhair_mobileapp/features/auth/domain/usecases/login_usecase.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_event.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/dashboard_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/report_models.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_reports_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/widgets/dashboard_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// A free-pricing delegate has NO self-service view of their price-variance
/// balance or per-sale breakdown anywhere in the app: التقارير shows exactly
/// the same two tabs as any other delegate, and the home dashboard shows
/// nothing. The fake repo throws on any member it doesn't implement, so any
/// leftover call into a variance endpoint would fail these tests.

class _FakeGps implements GpsService {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakePush implements PushNotificationService {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeLogin implements LoginUseCase {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeAuthRepo implements AuthRepository {
  final UserModel user;
  _FakeAuthRepo(this.user);
  @override
  Future<UserModel?> restoreSession() async => user;
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeRepo implements DelegateRepository {
  int dashboardCalls = 0;

  @override
  DashboardModel? getCachedDashboard() => null;

  @override
  Future<DashboardModel> getDashboard() async {
    dashboardCalls++;
    return DashboardModel.fromJson({
      'monthly_target': 1000, 'achieved_this_month': 500, 'target_percentage': 50,
      'commission_earned': 10, 'base_salary': 3000, 'penalties_total': 0,
      'advances_total': 0, 'bonus_total': 0, 'net_payable': 3010, 'current_month': '2026-09',
    });
  }

  @override
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo}) async => [];

  @override
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo}) async => [];

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

UserModel _user({required bool freePricing}) => UserModel(
      id: 1, name: 'مندوب', email: 'd@test.local', role: 'delegate', isActive: true,
      permissions: const [], hasActiveLoading: false, truckStockCount: 0,
      isFreePricingDelegate: freePricing,
    );

Future<({AuthBloc auth, DelegateBloc delegate, _FakeRepo repo})> _blocs(bool freePricing) async {
  final repo = _FakeRepo();
  final auth = AuthBloc(_FakeLogin(), _FakeAuthRepo(_user(freePricing: freePricing)), _FakePush());
  auth.add(AuthSessionRestoreRequested());
  await auth.stream.firstWhere((s) => s.runtimeType.toString() == 'AuthAuthenticated');
  return (auth: auth, delegate: DelegateBloc(repo, _FakeGps()), repo: repo);
}

Widget _host(({AuthBloc auth, DelegateBloc delegate, _FakeRepo repo}) b, Widget child) => MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: b.auth),
          BlocProvider<DelegateBloc>.value(value: b.delegate),
        ],
        child: child,
      ),
    );

void main() {
  testWidgets('home dashboard for a free-pricing delegate shows nothing and fetches nothing', (tester) async {
    final b = await _blocs(true);
    await tester.pumpWidget(_host(b, const Scaffold(body: SingleChildScrollView(child: DashboardSection()))));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('المستحق'), findsNothing);
    expect(find.textContaining('فروقات'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.text('الراتب الأساسي'), findsNothing);
    expect(b.repo.dashboardCalls, 0);
  });

  testWidgets('home dashboard for an ordinary delegate is unchanged (still fetches and shows payroll cards)',
      (tester) async {
    final b = await _blocs(false);
    await tester.pumpWidget(_host(b, const Scaffold(body: SingleChildScrollView(child: DashboardSection()))));
    await tester.pump();
    await tester.pump();

    expect(b.repo.dashboardCalls, 1);
    expect(find.text('الراتب الأساسي'), findsOneWidget);
  });

  for (final freePricing in [true, false]) {
    testWidgets('${freePricing ? 'free-pricing' : 'ordinary'} delegate\'s التقارير has exactly the two ordinary tabs',
        (tester) async {
      final b = await _blocs(freePricing);
      await tester.pumpWidget(_host(b, const DelegateReportsPage()));
      await tester.pump();

      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.text('تقرير المناطق'), findsOneWidget);
      expect(find.text('تقرير الأصناف'), findsOneWidget);
      expect(find.text('تقرير التحميلات'), findsNothing);
      expect(find.textContaining('المستحق'), findsNothing);
      expect(find.textContaining('فروقات'), findsNothing);
      // Period chips present on every tab, as for any delegate.
      expect(find.text('هذا الشهر'), findsOneWidget);
    });
  }
}
