import 'package:alkhair_mobileapp/core/security/sensitive_reveal_controller.dart';
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/push_notification_service.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';
import 'package:alkhair_mobileapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:alkhair_mobileapp/features/auth/domain/usecases/login_usecase.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_event.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/dashboard_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/price_variance_models.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/report_models.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_reports_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/widgets/dashboard_section.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/widgets/price_variance_dashboard_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the free-pricing delegate's "المستحق لك" balance is NOT on the home
/// dashboard, and is reachable only via التقارير → "تقرير التحميلات" behind the
/// biometric lock. Also proves an ordinary delegate is unaffected.

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
  int varianceCalls = 0;

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
  Future<PriceVarianceSummaryModel> getPriceVarianceSummary() async {
    varianceCalls++;
    return const PriceVarianceSummaryModel(priceVarianceBalance: 135.5, byLoading: []);
  }

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _ScriptedAuth implements DeviceAuthenticator {
  final List<DeviceAuthOutcome> outcomes;
  int calls = 0;
  _ScriptedAuth(this.outcomes);
  @override
  Future<DeviceAuthOutcome> authenticate(String reason) async {
    calls++;
    return outcomes.length > 1 ? outcomes.removeAt(0) : outcomes.first;
  }
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
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

/// Unmount first (the page defers a re-lock on dispose), then dispose the
/// controller — mirrors production, where the shared controller outlives pages.
Future<void> _unmountThenDispose(WidgetTester tester, SensitiveRevealController c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  c.dispose();
}

void main() {
  testWidgets('home dashboard for a free-pricing delegate shows nothing: no balance, no lock, no variance section, no fetch',
      (tester) async {
    final b = await _blocs(true);
    await tester.pumpWidget(_host(b, const DashboardSection()));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PriceVarianceDashboardSection), findsNothing);
    expect(find.textContaining('المستحق لك'), findsNothing);
    expect(find.textContaining('فروقات'), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    expect(find.byIcon(Icons.savings_rounded), findsNothing);
    // Not even the ordinary payroll cards (their zeros would look odd).
    expect(find.text('الراتب الأساسي'), findsNothing);
    expect(b.repo.dashboardCalls, 0);
    expect(b.repo.varianceCalls, 0);
  });

  testWidgets('home dashboard for an ordinary delegate is unchanged (still fetches and shows payroll cards)',
      (tester) async {
    final b = await _blocs(false);
    await tester.pumpWidget(_host(b, const DashboardSection()));
    await tester.pump();
    await tester.pump();

    expect(b.repo.dashboardCalls, 1);
    expect(find.text('الراتب الأساسي'), findsOneWidget);
    expect(find.byType(PriceVarianceDashboardSection), findsNothing);
  });

  testWidgets('ordinary delegate\'s التقارير has only the two ordinary tabs', (tester) async {
    final b = await _blocs(false);
    final reveal = SensitiveRevealController(_ScriptedAuth([DeviceAuthOutcome.success]));
    await tester.pumpWidget(MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: b.auth),
          BlocProvider<DelegateBloc>.value(value: b.delegate),
        ],
        child: DelegateReportsPage(revealController: reveal),
      ),
    ));
    await tester.pump();

    expect(find.text('تقرير المناطق'), findsOneWidget);
    expect(find.text('تقرير الأصناف'), findsOneWidget);
    expect(find.text('تقرير التحميلات'), findsNothing);
    await _unmountThenDispose(tester, reveal);
  });

  group('free-pricing delegate\'s التقارير', () {
    Future<({SensitiveRevealController reveal, _ScriptedAuth auth, _FakeRepo repo})> open(
      WidgetTester tester,
      List<DeviceAuthOutcome> outcomes,
    ) async {
      final b = await _blocs(true);
      final auth = _ScriptedAuth(outcomes);
      final reveal = SensitiveRevealController(auth);
      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: b.auth),
            BlocProvider<DelegateBloc>.value(value: b.delegate),
          ],
          child: DelegateReportsPage(revealController: reveal),
        ),
      ));
      await tester.pump();
      return (reveal: reveal, auth: auth, repo: b.repo);
    }

    testWidgets('has a third tab that looks like another report; nothing sensitive or authenticating before it is opened',
        (tester) async {
      final t = await open(tester, [DeviceAuthOutcome.success]);

      expect(find.text('تقرير التحميلات'), findsOneWidget);
      expect(find.textContaining('المستحق'), findsNothing);
      expect(find.textContaining('فروقات'), findsNothing);
      expect(t.auth.calls, 0);
      expect(t.repo.varianceCalls, 0);
      await _unmountThenDispose(tester, t.reveal);
    });

    testWidgets('opening the tab prompts immediately; a failed check leaves only a bland placeholder and nothing is fetched',
        (tester) async {
      final t = await open(tester, [DeviceAuthOutcome.failed]);

      await tester.tap(find.text('تقرير التحميلات'));
      await tester.pumpAndSettle();

      expect(t.auth.calls, 1);
      expect(t.reveal.isRevealed, isFalse);
      expect(find.text('هذا التقرير محمي'), findsOneWidget);
      expect(find.textContaining('المستحق لك'), findsNothing);
      expect(find.byType(PriceVarianceDashboardSection), findsNothing);
      expect(t.repo.varianceCalls, 0);
      await _unmountThenDispose(tester, t.reveal);
    });

    testWidgets('after a retry succeeds the balance appears; leaving the tab re-locks and removes it',
        (tester) async {
      final t = await open(tester, [DeviceAuthOutcome.failed, DeviceAuthOutcome.success]);

      await tester.tap(find.text('تقرير التحميلات'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-unlock-button')));
      await tester.pumpAndSettle();

      expect(t.reveal.isRevealed, isTrue);
      expect(find.byType(PriceVarianceDashboardSection), findsOneWidget);
      expect(find.text('المستحق لك'), findsOneWidget);
      expect(find.text('135.50 ج.م'), findsOneWidget);
      expect(t.repo.varianceCalls, 1);

      await tester.tap(find.text('تقرير المناطق'));
      await tester.pumpAndSettle();

      expect(t.reveal.isRevealed, isFalse);
      expect(find.textContaining('المستحق لك'), findsNothing);

      // Coming back asks again rather than showing the balance.
      await tester.tap(find.text('تقرير التحميلات'));
      await tester.pumpAndSettle();
      expect(find.text('135.50 ج.م'), findsOneWidget); // scripted auth succeeds again
      expect(t.auth.calls, 3);

      await _unmountThenDispose(tester, t.reveal);
    });
  });
}
