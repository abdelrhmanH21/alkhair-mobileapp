import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alkhair_mobileapp/core/utils/gps_service.dart';
import 'package:alkhair_mobileapp/core/widgets/dismiss_keyboard_on_tap.dart';
import 'package:alkhair_mobileapp/features/app_config/domain/repositories/app_config_repository.dart';
import 'package:alkhair_mobileapp/features/app_config/presentation/bloc/app_config_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/domain/repositories/delegate_repository.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/bloc/delegate_bloc.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/invoice_page.dart';

/// iOS doesn't dismiss the keyboard on a tap outside a focused field the
/// way Android does implicitly — see [DismissKeyboardOnTap]'s own doc
/// comment for the fix. These tests simulate that tap-outside gesture and
/// assert the keyboard/focus actually clears, which is exercisable headlessly
/// via flutter_test's `testTextInput.isVisible` (it mirrors whether a live
/// platform text-input connection — i.e. a shown keyboard — exists) without
/// any physical hardware.
class _UnusedAppConfigRepository implements AppConfigRepository {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Every method throws if called — none of the screens under test here
/// reach the repository during build or during the tap-to-dismiss gesture
/// itself (InvoicePage only touches it once a field gains focus or a sheet
/// is opened, neither of which these tests trigger).
class _UnusedDelegateRepository implements DelegateRepository {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'DelegateRepository.${invocation.memberName} not used by this test');
}

void main() {
  testWidgets(
    'plain screen: tapping blank space outside a focused TextField dismisses the keyboard',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => DismissKeyboardOnTap(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focusNode),
              // Blank space with no widget of its own to hit-test against —
              // exactly what HitTestBehavior.opaque is needed for.
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'tapping the field should bring up the keyboard');

      // Tap blank space well below the field, still inside the Scaffold.
      await tester.tapAt(const Offset(200, 500));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'tap-outside should dismiss the keyboard, matching Android');
    },
  );

  testWidgets(
    'bottom sheet with a form: tapping blank space inside the sheet dismisses the '
    'keyboard without dismissing the sheet itself',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(MaterialApp(
        builder: (ctx, child) => DismissKeyboardOnTap(child: child!),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  builder: (_) => SizedBox(
                    height: 300,
                    child: Column(
                      children: [
                        TextField(focusNode: focusNode),
                        // Blank area of the sheet's own visible content,
                        // below the field — must dismiss the keyboard but
                        // not the sheet.
                        const Expanded(
                          child: SizedBox.expand(key: Key('sheetBlankArea')),
                        ),
                      ],
                    ),
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
      expect(find.byType(TextField), findsOneWidget,
          reason: 'sheet should be open');

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      // Tap the sheet's own blank area (below the field, still well within
      // the sheet's bounds — not the modal barrier behind it). An empty
      // SizedBox contributes nothing to hit-testing on its own — that's the
      // whole point being verified: the tap only lands because it bubbles
      // up to the ancestor DismissKeyboardOnTap, whose opaque behavior
      // catches it. warnIfMissed is expected to trip here for that reason.
      await tester.tap(find.byKey(const Key('sheetBlankArea')),
          warnIfMissed: false);
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'keyboard should dismiss');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the sheet itself must stay open — only the keyboard dismisses');
    },
  );

  testWidgets(
    'invoice entry screen: tapping blank space outside the discount field dismisses the keyboard',
    (tester) async {
      final bloc = DelegateBloc(_UnusedDelegateRepository(), GpsService());
      addTearDown(bloc.close);
      final appConfigBloc = AppConfigBloc(_UnusedAppConfigRepository());
      addTearDown(appConfigBloc.close);

      await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider<DelegateBloc>.value(value: bloc),
          BlocProvider<AppConfigBloc>.value(value: appConfigBloc),
        ],
        child: MaterialApp(
          builder: (ctx, child) => DismissKeyboardOnTap(child: child!),
          home: const InvoicePage(),
        ),
      ));
      await tester.pump();

      // The discount field, from _TotalsCard — same screen as the reported
      // screenshot (keyboard covering the bottom nav with no way to dismiss).
      // Deliberately NOT the client-search field: focusing that one triggers
      // a live customer-list fetch through the bloc, which this test's
      // repository fake doesn't implement.
      final discountField = find.byKey(const Key('invoiceDiscountField'));
      expect(discountField, findsOneWidget);

      await tester.tap(discountField);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // Tap blank space below the submit button — mirrors the reported bug
      // (keyboard covering the bottom nav with no way to dismiss it). Same
      // "empty SizedBox catches nothing itself" reasoning as the sheet test
      // above — warnIfMissed is expected to trip.
      final blankSpacer = find.byKey(const Key('invoiceFormBottomSpacer'));
      await tester.ensureVisible(blankSpacer);
      await tester.pump();
      await tester.tap(blankSpacer, warnIfMissed: false);
      await tester.pump();

      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'tap-outside on the invoice screen should free the bottom '
              'nav from behind the keyboard, matching Android');
    },
  );
}
