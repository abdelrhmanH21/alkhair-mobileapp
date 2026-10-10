import 'dart:convert';

import 'package:alkhair_mobileapp/core/security/sensitive_reveal_controller.dart';
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/utils/push_notification_service.dart';
import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:alkhair_mobileapp/features/auth/data/models/user_model.dart';
import 'package:alkhair_mobileapp/features/auth/domain/repositories/auth_repository.dart';
import 'package:alkhair_mobileapp/features/auth/domain/usecases/login_usecase.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:alkhair_mobileapp/features/auth/presentation/bloc/auth_event.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/client_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/report_models.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/delegate_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// كشف حساب عميل — the fixture below is the REAL, unmodified response of
/// GET /v1/mobile/admin/customers/19/statement from production on
/// 2026-09-30 (customer "اسواق بدر": delegate invoices, delegate + admin
/// collections, and three جرد المديونيات adjustments). Its running
/// balance_after chain must end exactly at that customer's real
/// Customer.balance (7520.00, also returned as current_balance).
const _customer19Statement = '''
{
 "customer": {
  "id": 19,
  "name": "اسواق بدر",
  "phone": "0",
  "region": "العجمي - هانوفيل",
  "opening_balance": 4070,
  "current_balance": 7520
 },
 "period": {
  "from": null,
  "to": null
 },
 "data": [
  {
   "type": "opening",
   "type_label": "رصيد أول المدة",
   "date": "2026-06-28 22:38",
   "reference_id": null,
   "invoice_number": null,
   "actor": null,
   "description": "الرصيد الافتتاحي للعميل",
   "amount": 4070,
   "balance_after": 4070
  },
  {
   "type": "invoice",
   "type_label": "فاتورة (آجل)",
   "date": "2026-07-04 21:01",
   "reference_id": 11,
   "invoice_number": "DINV-000011",
   "actor": "الملواني",
   "description": "فاتورة DINV-000011 — صافي 650.00، نقدي 0.00",
   "amount": 650,
   "balance_after": 4720
  },
  {
   "type": "invoice",
   "type_label": "فاتورة (آجل)",
   "date": "2026-07-04 22:01",
   "reference_id": 12,
   "invoice_number": "DINV-000012",
   "actor": "الملواني",
   "description": "فاتورة DINV-000012 — صافي 550.00، نقدي 400.00",
   "amount": 150,
   "balance_after": 4870
  },
  {
   "type": "collection",
   "type_label": "تحصيل",
   "date": "2026-07-17 08:02",
   "reference_id": 13,
   "invoice_number": null,
   "actor": "الملواني",
   "description": "سند تحصيل #13",
   "amount": -1000,
   "balance_after": 3870
  },
  {
   "type": "invoice",
   "type_label": "فاتورة (آجل)",
   "date": "2026-07-17 08:49",
   "reference_id": 23,
   "invoice_number": "DINV-000023",
   "actor": "الملواني",
   "description": "فاتورة DINV-000023 — صافي 330.00، نقدي 320.00",
   "amount": 10,
   "balance_after": 3880
  },
  {
   "type": "collection",
   "type_label": "تحصيل",
   "date": "2026-07-17 08:50",
   "reference_id": 14,
   "invoice_number": null,
   "actor": "الملواني",
   "description": "سند تحصيل #14",
   "amount": -10,
   "balance_after": 3870
  },
  {
   "type": "collection",
   "type_label": "تحصيل",
   "date": "2026-07-17 12:40",
   "reference_id": 16,
   "invoice_number": null,
   "actor": "الملواني",
   "description": "سند تحصيل #16",
   "amount": -100,
   "balance_after": 3770
  },
  {
   "type": "debt_audit",
   "type_label": "تعديل جرد",
   "date": "2026-07-24 23:37",
   "reference_id": 16,
   "invoice_number": null,
   "actor": "مدير العمليات",
   "description": "جرد المديونيات: من 3770.00 إلى 9350.00",
   "amount": 5580,
   "balance_after": 9350,
   "old_value": 3770,
   "new_value": 9350,
   "notes": null
  },
  {
   "type": "debt_audit",
   "type_label": "تعديل جرد",
   "date": "2026-08-04 12:43",
   "reference_id": 43,
   "invoice_number": null,
   "actor": "admin",
   "description": "جرد المديونيات: من 9350.00 إلى 5000.00",
   "amount": -4350,
   "balance_after": 5000,
   "old_value": 9350,
   "new_value": 5000,
   "notes": null
  },
  {
   "type": "collection",
   "type_label": "تحصيل",
   "date": "2026-09-02 20:43",
   "reference_id": 38,
   "invoice_number": null,
   "actor": "محمد ناصر",
   "description": "سند تحصيل #38",
   "amount": -1000,
   "balance_after": 4000
  },
  {
   "type": "invoice",
   "type_label": "فاتورة (آجل)",
   "date": "2026-09-02 20:55",
   "reference_id": 62,
   "invoice_number": "DINV-000062",
   "actor": "محمد ناصر",
   "description": "فاتورة DINV-000062 — صافي 330.00، نقدي 0.00",
   "amount": 330,
   "balance_after": 4330
  },
  {
   "type": "debt_audit",
   "type_label": "تعديل جرد",
   "date": "2026-09-19 11:21",
   "reference_id": 104,
   "invoice_number": null,
   "actor": "admin",
   "description": "جرد المديونيات: من 4330.00 إلى 7520.00",
   "amount": 3190,
   "balance_after": 7520,
   "old_value": 4330,
   "new_value": 7520,
   "notes": null
  }
 ],
 "summary": {
  "opening_balance": 4070,
  "total_debit": 9910,
  "total_credit": 6460,
  "closing_balance": 7520,
  "current_balance": 7520,
  "unexplained_total": 0,
  "row_count": 12
 }
}
''';

CustomerLedgerModel _realLedger() =>
    CustomerLedgerModel.fromJson(jsonDecode(_customer19Statement) as Map<String, dynamic>);

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
  final List<int> ledgerRequests = [];

  @override
  Future<List<TreasuryReportRowModel>> fetchTreasuryReport({String? period, String? dateFrom, String? dateTo}) async => [];
  @override
  Future<List<SupplierReportRowModel>> fetchSupplierReport({String? period, String? dateFrom, String? dateTo}) async => [];
  @override
  Future<List<ClientModel>> searchCustomers(String query) async =>
      [const ClientModel(id: 19, name: 'اسواق بدر', phone: '0', balance: 7520)];
  @override
  Future<CustomerLedgerModel> fetchCustomerLedger(int customerId, {String? dateFrom, String? dateTo}) async {
    ledgerRequests.add(customerId);
    return _realLedger();
  }

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
  group('real customer statement (production fixture)', () {
    test('running balance_after chain ends exactly at the real Customer.balance', () {
      final l = _realLedger();

      expect(l.currentBalance, 7520.0);
      expect(l.rows.first.type, 'opening');
      expect(l.rows.first.balanceAfter, 4070.0);
      for (var i = 1; i < l.rows.length; i++) {
        expect(l.rows[i].balanceAfter, closeTo(l.rows[i - 1].balanceAfter + l.rows[i].amount, 0.001),
            reason: 'row $i (${l.rows[i].type}) must equal previous balance + its amount');
      }
      expect(l.rows.last.balanceAfter, l.currentBalance);
      expect(l.closingBalance, l.currentBalance);
      expect(l.unexplainedTotal, 0);
    });

    test('has every row type, and each جرد old value is the replayed balance before it', () {
      final l = _realLedger();
      final types = l.rows.map((r) => r.type).toSet();
      expect(types, containsAll(<String>['invoice', 'collection', 'debt_audit']));

      final audits = <CustomerLedgerRowModel>[];
      for (var i = 0; i < l.rows.length; i++) {
        final r = l.rows[i];
        if (r.type != 'debt_audit') continue;
        audits.add(r);
        expect(r.typeLabel, 'تعديل جرد');
        expect(r.oldValue, l.rows[i - 1].balanceAfter);
        expect(r.newValue, r.balanceAfter);
        expect(r.actor, isNotNull);
      }
      expect(audits.map((a) => a.oldValue), [3770.0, 9350.0, 4330.0]);
      expect(audits.map((a) => a.newValue), [9350.0, 5000.0, 7520.0]);

      final invoice = l.rows.firstWhere((r) => r.type == 'invoice');
      expect(invoice.invoiceNumber, 'DINV-000011');
      expect(invoice.amount, 650.0);
    });

    test('export payload: one line per row, closing total = current debt', () {
      final data = customerLedgerExportData(_realLedger());
      expect(data.title, 'كشف حساب عميل — اسواق بدر');
      expect(data.period, 'كامل السجل');
      expect(data.headers, ['التاريخ', 'النوع', 'البيان', 'المبلغ', 'رصيد بعدها']);
      expect(data.rows, hasLength(12));
      expect(data.rows.first[3], '-', reason: 'opening row has no movement amount');
      expect(data.rows.last[4], '7,520.00');
      expect(data.totals!.last, '7,520.00');
    });
  });

  testWidgets('admin opens كشف حساب عميل, picks a customer, sees the full ledger', (tester) async {
    final remote = _FakeAdminRemote();
    await _pump(tester, role: 'admin', remote: remote);

    expect(find.text('هذا الشهر'), findsOneWidget);
    // Last admin tab in a scrollable TabBar — may start off-screen.
    await tester.ensureVisible(find.text('كشف حساب عميل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كشف حساب عميل'));
    await tester.pumpAndSettle();
    // Own optional range instead of the shared period chips.
    expect(find.text('هذا الشهر'), findsNothing);
    expect(find.text('كامل السجل'), findsOneWidget);
    expect(find.byIcon(Icons.person_add), findsNothing, reason: 'read-only picker');

    await tester.enterText(find.byType(TextField), 'بدر');
    await tester.pumpAndSettle();
    await tester.tap(find.text('اسواق بدر').last);
    await tester.pumpAndSettle();

    expect(remote.ledgerRequests, [19]);
    expect(find.text('تصدير PDF'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('إجمالي المديونية الحالية'), 300,
        scrollable: find
            .descendant(of: find.byType(CustomerLedgerReportView), matching: find.byType(Scrollable))
            .first);
    expect(find.text('إجمالي المديونية الحالية'), findsOneWidget);
    expect(find.text('رصيد بعدها: 7,520.00'), findsOneWidget);
  });

  testWidgets('a delegate never gets the customer statement tab', (tester) async {
    await _pump(tester, role: 'delegate', remote: _FakeAdminRemote());
    expect(find.text('كشف حساب عميل'), findsNothing);
  });
}
