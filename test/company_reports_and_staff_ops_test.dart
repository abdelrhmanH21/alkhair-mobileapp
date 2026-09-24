import 'package:alkhair_mobileapp/core/security/sensitive_reveal_controller.dart';
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/push_notification_service.dart';
import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';
import 'package:alkhair_mobileapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:alkhair_mobileapp/features/auth/domain/usecases/login_usecase.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_event.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/breakdown_models.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/report_models.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// تقرير الخزائن / تقرير الموردين (admin/manager only, same page + period
/// chips as the region/product reports) and the "مندوب حر السعر" staff-op
/// redirect as the app models it.

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
  @override
  Future<List<RegionReportRowModel>> getReportByRegion({String? period, String? dateFrom, String? dateTo}) async => [];
  @override
  Future<List<ProductReportRowModel>> getReportByProduct({String? period, String? dateFrom, String? dateTo}) async => [];
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _FakeAdminRemote implements AdminRemoteDataSource {
  final List<String?> periods = [];

  @override
  Future<List<TreasuryReportRowModel>> fetchTreasuryReport({String? period, String? dateFrom, String? dateTo}) async {
    periods.add(period);
    return [
      TreasuryReportRowModel.fromJson({
        'treasury_id': 1, 'treasury_name': 'الخزينة الرئيسية', 'balance': 1150,
        'total_credit': 1000, 'total_debit': 250, 'net_movement': 750, 'transaction_count': 2,
      }),
    ];
  }

  @override
  Future<List<SupplierReportRowModel>> fetchSupplierReport({String? period, String? dateFrom, String? dateTo}) async => [
        SupplierReportRowModel.fromJson({
          'supplier_id': 3, 'supplier_name': 'مورد أ', 'balance': 300,
          'total_purchases': 600, 'total_paid': 300, 'purchase_count': 2,
        }),
      ];

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _NoAuth implements DeviceAuthenticator {
  @override
  Future<DeviceAuthOutcome> authenticate(String reason) async => DeviceAuthOutcome.failed;
}

Future<void> _pump(WidgetTester tester, {required String role, required _FakeAdminRemote remote}) async {
  final auth = AuthBloc(
    _FakeLogin(),
    _FakeAuthRepo(UserModel(
      id: 1, name: 'x', email: 'x@test.local', role: role, isActive: true,
      permissions: const [], hasActiveLoading: false, truckStockCount: 0,
    )),
    _FakePush(),
  );
  auth.add(AuthSessionRestoreRequested());
  await auth.stream.firstWhere((s) => s.runtimeType.toString() == 'AuthAuthenticated');
  final delegate = DelegateBloc(_FakeRepo(), _FakeGps());
  final reveal = SensitiveRevealController(_NoAuth());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    reveal.dispose();
    await delegate.close();
    await auth.close();
  });

  await tester.pumpWidget(MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: auth),
        BlocProvider<DelegateBloc>.value(value: delegate),
      ],
      child: DelegateReportsPage(revealController: reveal, adminRemote: remote),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('admin gets تقرير الخزائن / تقرير الموردين with the same period selection', (tester) async {
    final remote = _FakeAdminRemote();
    await _pump(tester, role: 'admin', remote: remote);

    expect(find.text('تقرير الخزائن'), findsOneWidget);
    expect(find.text('تقرير الموردين'), findsOneWidget);
    expect(remote.periods, ['month']);

    await tester.tap(find.text('تقرير الخزائن'));
    await tester.pumpAndSettle();
    expect(find.text('الخزينة الرئيسية'), findsOneWidget);
    expect(find.text('1150.00'), findsOneWidget);
    expect(find.text('تصدير PDF'), findsOneWidget);
    expect(find.text('تصدير Excel'), findsOneWidget);

    // Same chips drive the new tabs too.
    await tester.tap(find.text('هذا الأسبوع'));
    await tester.pumpAndSettle();
    expect(remote.periods, ['month', 'week']);

    await tester.tap(find.text('تقرير الموردين'));
    await tester.pumpAndSettle();
    expect(find.text('مورد أ'), findsOneWidget);
    expect(find.text('600.00'), findsOneWidget);
  });

  testWidgets('a delegate never sees or fetches the company-wide reports', (tester) async {
    final remote = _FakeAdminRemote();
    await _pump(tester, role: 'delegate', remote: remote);

    expect(find.text('تقرير الخزائن'), findsNothing);
    expect(find.text('تقرير الموردين'), findsNothing);
    expect(remote.periods, isEmpty);
  });

  group('free-pricing staff operations', () {
    test('ledger rows for سلفة/جزاء/مكافأة get their own labels', () {
      PriceVarianceTransactionModel tx(String type, num amount) => PriceVarianceTransactionModel.fromJson({
            'id': 1, 'type': type, 'amount': amount, 'balance_after': -50,
            'created_at': '2026-09-24T10:00:00Z', 'notes': null,
          });
      expect(tx('advance', -150).typeLabel, 'سلفة');
      expect(tx('penalty', -30).typeLabel, 'جزاء');
      expect(tx('bonus', 45).typeLabel, 'مكافأة');
      expect(tx('accrual', 10).typeLabel, 'فرق سعر بيع');
      expect(tx('payout', -10).typeLabel, 'صرف');
      expect(tx('advance', -150).balanceAfter, -50, reason: 'balance may go negative');
    });

    test('advance/penalty/bonus rows carry the redirected flag', () {
      expect(AdvanceModel.fromJson({'id': 1, 'amount': 150, 'type': 'cash', 'redirected_to_price_variance': true})
          .redirectedToPriceVariance, isTrue);
      expect(PenaltyModel.fromJson({'id': 1, 'amount': 30, 'reason': 'x'}).redirectedToPriceVariance, isFalse);
      expect(BonusModel.fromJson({'id': 1, 'amount': 45, 'redirected_to_price_variance': true})
          .redirectedToPriceVariance, isTrue);
      expect(StaffModel.fromJson({'id': 9, 'name': 'طارق', 'is_free_pricing_delegate': true}).isFreePricingDelegate,
          isTrue);
    });
  });
}
