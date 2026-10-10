import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/settlement_summary_model.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/settlement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// تسليم: cash and wallet are optional — blank means 0, 0 is valid in either
/// or both, and the submit button is enabled whenever there is an active
/// loading; no validation error / blocking dialog for blank or zero.

class _FakeGps implements GpsService {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeRepo implements DelegateRepository {
  final List<({double cash, double wallet})> submitted = [];

  @override
  Future<SettlementSummaryModel> getSettlementSummary() async => SettlementSummaryModel.fromJson({
        'loading': {'id': 11},
        'total_invoices': 1,
        'total_net': 600,
        'total_cash': 600,
        'expected_cash': 600,
      });

  @override
  Future<void> submitSettlementRequest({required double cashAmount, required double walletAmount, String? notes}) async {
    submitted.add((cash: cashAmount, wallet: walletAmount));
  }

  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<(_FakeRepo, DelegateBloc)> _pump(WidgetTester tester) async {
  final repo = _FakeRepo();
  final bloc = DelegateBloc(repo, _FakeGps());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await bloc.close();
  });
  await tester.pumpWidget(MaterialApp(
    home: BlocProvider<DelegateBloc>.value(value: bloc, child: const SettlementPage()),
  ));
  await tester.pump();
  await tester.pump();
  return (repo, bloc);
}

Finder get _submitButton => find.widgetWithText(ElevatedButton, 'إرسال طلب التسليم');

void main() {
  testWidgets('both fields blank: button enabled, submits 0 / 0 without any error', (tester) async {
    final (repo, _) = await _pump(tester);

    expect(_submitButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(_submitButton).onPressed, isNotNull);

    await tester.tap(_submitButton);
    await tester.pump();
    await tester.pump();

    expect(repo.submitted, [(cash: 0.0, wallet: 0.0)]);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('explicit 0 in both fields submits 0 / 0', (tester) async {
    final (repo, _) = await _pump(tester);
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.tap(_submitButton);
    await tester.pump();
    await tester.pump();
    expect(repo.submitted, [(cash: 0.0, wallet: 0.0)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Arabic digits typed in the cash field are sent as a Latin number', (tester) async {
    final (repo, _) = await _pump(tester);
    await tester.enterText(find.byType(TextField).at(0), '٥٩٩٫٥');
    expect(find.text('599.5'), findsOneWidget);
    await tester.tap(_submitButton);
    await tester.pump();
    await tester.pump();
    expect(repo.submitted, [(cash: 599.5, wallet: 0.0)]);
  });
}
