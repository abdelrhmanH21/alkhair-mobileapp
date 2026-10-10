import 'dart:ui' as ui;

import 'package:alkhair_mobileapp/app.dart' show alKhairAppBuilder;
import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/features/admin/data/datasources/admin_remote_datasource.dart';
import 'package:alkhair_mobileapp/features/admin/data/models/admin_models.dart';
import 'package:alkhair_mobileapp/features/admin/presentation/bloc/admin_bloc.dart';
import 'package:alkhair_mobileapp/features/admin/presentation/pages/settle_delegate_page.dart';
import 'package:alkhair_mobileapp/features/app_config/domain/repositories/app_config_repository.dart';
import 'package:alkhair_mobileapp/features/app_config/presentation/bloc/app_config_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/client_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/customer_region_model.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/settlement_summary_model.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/invoice_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/settlement_page.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/widgets/add_client_sheet.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/widgets/client_search_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Part 3 — "tap outside closes the keyboard" on the REAL screens, under
/// the conditions a phone actually produces (the old root
/// GestureDetector.onTap passed its idealised widget tests but failed on
/// devices):
///  - Android reports its own touch slop (8 dp) — smaller than the 18 dp a
///    tap recognizer tolerates — so a scroll view's drag recognizer claims
///    a slightly wobbly finger tap;
///  - most of a screen is tappable (cards, list tiles, dropdowns), and a
///    child's tap recognizer always beats the root's.
/// Every test here mounts the app's real MaterialApp.builder.

class _NoAppConfig implements AppConfigRepository {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Repo implements DelegateRepository {
  @override
  Future<SettlementSummaryModel> getSettlementSummary() async => SettlementSummaryModel.fromJson({
        'loading': {'id': 11},
        'total_invoices': 1,
        'total_net': 600,
        'total_cash': 600,
        'expected_cash': 600,
      });
  @override
  Future<List<CustomerRegionModel>> getCustomerRegions() async => const [];
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _AdminRemote implements AdminRemoteDataSource {
  @override
  Future<ShiftSummaryModel> fetchShiftSummary(int delegateId) async => ShiftSummaryModel.fromJson({
        'total_invoices': 3,
        'total_gross': 900,
        'total_net': 900,
        'total_cash': 900,
        'settlement_request_id': 4,
        'declared_cash_amount': '900.00',
        'declared_wallet_amount': '0.00',
      });
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Gps implements GpsService {
  @override
  Never noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Android-like gesture settings: 8 dp platform touch slop.
void _deviceGestures(WidgetTester tester) {
  tester.view.gestureSettings = ui.GestureSettings(physicalTouchSlop: 8 * tester.view.devicePixelRatio);
  addTearDown(tester.view.resetGestureSettings);
}

/// A real finger tap: down, a 10 px wobble, up — well within the 18 dp
/// tap tolerance, but past Android's 8 dp drag slop.
Future<void> _fingerTap(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 40));
  await g.moveBy(const Offset(0, 10));
  await tester.pump(const Duration(milliseconds: 40));
  await g.up();
  await tester.pump();
}

Future<DelegateBloc> _pumpDelegateScreen(WidgetTester tester, Widget home) async {
  final bloc = DelegateBloc(_Repo(), _Gps());
  final cfg = AppConfigBloc(_NoAppConfig());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await bloc.close();
    await cfg.close();
  });
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider<DelegateBloc>.value(value: bloc),
      BlocProvider<AppConfigBloc>.value(value: cfg),
    ],
    child: MaterialApp(builder: alKhairAppBuilder, home: home),
  ));
  await tester.pump();
  await tester.pump();
  return bloc;
}

void main() {
  testWidgets('invoice screen (number keypad): a wobbly finger tap on blank space inside the scroll view closes it',
      (tester) async {
    _deviceGestures(tester);
    await _pumpDelegateScreen(tester, const InvoicePage());
    final discount = find.byKey(const Key('invoiceDiscountField'));
    await tester.tap(discount);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    final spacer = find.byKey(const Key('invoiceFormBottomSpacer'));
    await tester.ensureVisible(spacer);
    await tester.pump();
    await _fingerTap(tester, tester.getCenter(spacer));

    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('settlement screen (number keypad): tapping the summary card closes it', (tester) async {
    _deviceGestures(tester);
    await _pumpDelegateScreen(tester, const SettlementPage());
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await _fingerTap(tester, tester.getCenter(find.text('ملخص الوردية')));
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('add-client bottom sheet (text keypad): blank tap inside the sheet closes the keyboard, sheet stays',
      (tester) async {
    _deviceGestures(tester);
    await _pumpDelegateScreen(
      tester,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => BlocProvider.value(
                  value: ctx.read<DelegateBloc>(),
                  child: AddClientSheet(onClientAdded: (_) {}),
                ),
              ),
              child: const Text('عميل جديد'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('عميل جديد'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'اسم العميل *');
    await tester.tap(name);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    // Blank area just under the sheet's top edge — inside the sheet.
    final sheetTop = tester.getTopLeft(find.byType(AddClientSheet));
    await _fingerTap(tester, sheetTop + const Offset(40, 6));
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(AddClientSheet), findsOneWidget, reason: 'only the keyboard closes, not the sheet');
  });

  testWidgets('admin settle form (number keypad): tapping a summary row closes it', (tester) async {
    _deviceGestures(tester);
    final admin = AdminBloc(_AdminRemote());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await admin.close();
    });
    await tester.pumpWidget(BlocProvider<AdminBloc>.value(
      value: admin,
      child: const MaterialApp(
        builder: alKhairAppBuilder,
        home: SettleDelegatePage(
          delegate: DelegateModel(id: 2, name: 'مندوب', email: 'd@x', isActive: true, hasActiveShift: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(TextField, 'النقد الفعلي المستلم'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await _fingerTap(tester, tester.getCenter(find.text('إجمالي المبيعات')));
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('dialog: tapping a tappable list tile inside it closes the keyboard (and the tile still fires)',
      (tester) async {
    var picked = 0;
    await tester.pumpWidget(MaterialApp(
      builder: alKhairAppBuilder,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog(
                context: ctx,
                builder: (_) => AlertDialog(
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const TextField(),
                    ListTile(title: const Text('خيار'), onTap: () => picked++),
                  ]),
                ),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('خيار'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(picked, 1);
  });

  group('does not interfere', () {
    Widget form({required VoidCallback onButton, TextEditingController? a}) => MaterialApp(
          builder: alKhairAppBuilder,
          home: Scaffold(
            body: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                TextField(key: const Key('a'), controller: a),
                const TextField(key: Key('b')),
                ElevatedButton(onPressed: onButton, child: const Text('زر')),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );

    testWidgets('tapping another field moves focus and keeps the keyboard', (tester) async {
      await tester.pumpWidget(form(onButton: () {}));
      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('b')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      final b = tester.state<EditableTextState>(
          find.descendant(of: find.byKey(const Key('b')), matching: find.byType(EditableText)));
      expect(b.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('buttons still fire', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(form(onButton: () => pressed++));
      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();
      await tester.tap(find.text('زر'));
      await tester.pump();
      expect(pressed, 1);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('a long press is not a tap, and an active text selection is left alone', (tester) async {
      final a = TextEditingController(text: 'نص طويل للتجربة');
      addTearDown(a.dispose);
      await tester.pumpWidget(form(onButton: () {}, a: a));
      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();

      final g = await tester.startGesture(tester.getCenter(find.text('زر')) + const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue, reason: 'long press ≠ tap');

      a.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.text('زر')) + const Offset(0, 120));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue, reason: 'mid-selection: selection keeps working');
    });

    testWidgets('dragging the main scroll view dismisses (onDrag) — a scroll is never mistaken for a tap',
        (tester) async {
      await tester.pumpWidget(form(onButton: () {}));
      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    });
  });

  testWidgets('customer search results close when focus leaves (outside tap)', (tester) async {
    final focus = FocusNode();
    final ctrl = TextEditingController();
    addTearDown(focus.dispose);
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: alKhairAppBuilder,
      home: Scaffold(
        body: Column(children: [
          ClientSearchField(
            controller: ctrl,
            focusNode: focus,
            results: const [ClientModel(id: 1, name: 'أحمد', phone: '0100', balance: 0)],
            isLoading: false,
            selectedClient: null,
            onSearch: (_) {},
            onSelect: (_) {},
          ),
          const Expanded(child: SizedBox.expand(key: Key('blank'))),
        ]),
      ),
    ));
    expect(find.text('أحمد'), findsNothing, reason: 'no list while the field is not focused');
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('أحمد'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byKey(const Key('blank'))));
    await tester.pump();
    expect(find.text('أحمد'), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('iOS number pad: a "تم" bar sits above it and closes it; none for a text keyboard', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(
      builder: alKhairAppBuilder,
      home: Scaffold(
        body: Column(children: [
          TextField(key: Key('num'), keyboardType: TextInputType.numberWithOptions(decimal: true)),
          TextField(key: Key('text')),
        ]),
      ),
    ));
    await tester.tap(find.byKey(const Key('text')));
    await tester.pump();
    expect(find.byKey(const Key('numeric-done-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('num')));
    await tester.pump();
    expect(find.byKey(const Key('numeric-done-bar')), findsOneWidget);
    await tester.tap(find.text('تم'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(const Key('numeric-done-bar')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
