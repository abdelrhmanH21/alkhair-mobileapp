import 'package:alkhair_mobileapp/core/security/sensitive_reveal_controller.dart';
import 'package:alkhair_mobileapp/core/widgets/masked_amount.dart';
import 'package:alkhair_mobileapp/features/delegate/data/models/price_variance_models.dart';
import 'package:alkhair_mobileapp/features/delegate/presentation/pages/price_variance_loading_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted stand-in for local_auth: returns queued outcomes, records calls,
/// and can hold a prompt open to simulate the system dialog being on screen.
class FakeAuthenticator implements DeviceAuthenticator {
  final List<DeviceAuthOutcome> outcomes;
  int calls = 0;
  Future<void>? hold;
  FakeAuthenticator(this.outcomes);

  @override
  Future<DeviceAuthOutcome> authenticate(String reason) async {
    calls++;
    if (hold != null) await hold;
    return outcomes.length > 1 ? outcomes.removeAt(0) : outcomes.first;
  }
}

const _loading = PriceVarianceLoadingModel(
  loadingId: 1,
  date: '2026-09-20',
  status: 'completed',
  loadingVarianceTotal: 195,
  lines: [
    PriceVarianceLineModel(
      invoiceId: 7,
      invoiceNumber: 'DINV-000007',
      customerName: 'عميل تجريبي',
      productName: 'جبنة',
      quantity: 2,
      referencePrice: 255,
      chargedPrice: 300,
      variance: 90,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SensitiveRevealController', () {
    test('starts locked', () {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      expect(c.isRevealed, isFalse);
    });

    test('successful auth reveals', () async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      expect(await c.requestReveal(), RevealResult.revealed);
      expect(c.isRevealed, isTrue);
      c.dispose();
    });

    test('failed / canceled / locked-out / error auth all stay masked', () async {
      final cases = {
        DeviceAuthOutcome.failed: RevealResult.denied,
        DeviceAuthOutcome.canceled: RevealResult.canceled,
        DeviceAuthOutcome.lockedOut: RevealResult.lockedOut,
        DeviceAuthOutcome.error: RevealResult.error,
      };
      for (final entry in cases.entries) {
        final c = SensitiveRevealController(FakeAuthenticator([entry.key]));
        expect(await c.requestReveal(), entry.value, reason: '${entry.key}');
        expect(c.isRevealed, isFalse, reason: '${entry.key}');
        c.dispose();
      }
    });

    test('device with no screen lock at all reveals, flagged as unprotected (never permanently blocked)', () async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.unavailable]));
      expect(await c.requestReveal(), RevealResult.revealedUnprotected);
      expect(c.isRevealed, isTrue);
      c.dispose();
    });

    test('can retry after a failed attempt', () async {
      final auth = FakeAuthenticator([DeviceAuthOutcome.failed, DeviceAuthOutcome.success]);
      final c = SensitiveRevealController(auth);
      expect(await c.requestReveal(), RevealResult.denied);
      expect(await c.requestReveal(), RevealResult.revealed);
      expect(c.isRevealed, isTrue);
      c.dispose();
    });

    test('a second request while already revealed does not re-prompt', () async {
      final auth = FakeAuthenticator([DeviceAuthOutcome.success]);
      final c = SensitiveRevealController(auth);
      await c.requestReveal();
      expect(await c.requestReveal(), RevealResult.ignored);
      expect(auth.calls, 1);
      c.dispose();
    });

    test('a second request while a prompt is open is ignored (no stacked prompts)', () async {
      final gate = Future<void>.delayed(const Duration(milliseconds: 20));
      final auth = FakeAuthenticator([DeviceAuthOutcome.success])..hold = gate;
      final c = SensitiveRevealController(auth);
      final first = c.requestReveal();
      expect(c.isAuthenticating, isTrue);
      expect(await c.requestReveal(), RevealResult.ignored);
      expect(await first, RevealResult.revealed);
      expect(auth.calls, 1);
      c.dispose();
    });

    test('manual lock re-masks immediately', () async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      await c.requestReveal();
      c.lock();
      expect(c.isRevealed, isFalse);
      c.dispose();
    });

    test('re-locks when the app goes to the background', () async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      await c.requestReveal();
      c.didChangeAppLifecycleState(AppLifecycleState.inactive); // e.g. Face ID sheet: no re-lock
      expect(c.isRevealed, isTrue);
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(c.isRevealed, isFalse);
      c.dispose();
    });

    test('backgrounding while the auth prompt itself is open does not break the reveal', () async {
      final gate = Future<void>.delayed(const Duration(milliseconds: 20));
      final auth = FakeAuthenticator([DeviceAuthOutcome.success])..hold = gate;
      final c = SensitiveRevealController(auth);
      final pending = c.requestReveal();
      c.didChangeAppLifecycleState(AppLifecycleState.paused); // system prompt side effect
      expect(await pending, RevealResult.revealed);
      expect(c.isRevealed, isTrue);
      c.dispose();
    });

    testWidgets('auto re-locks exactly after the 60s reveal window', (tester) async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      await c.requestReveal();
      expect(c.isRevealed, isTrue);

      await tester.pump(const Duration(seconds: 59));
      expect(c.isRevealed, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(c.isRevealed, isFalse);
      c.dispose();
    });
  });

  group('PriceVarianceLoadingDetailPage masking', () {
    Widget host(SensitiveRevealController c) => MaterialApp(
          home: PriceVarianceLoadingDetailPage(loading: _loading, revealController: c),
        );

    testWidgets('every money figure is masked until authenticated; non-sensitive data always shows', (tester) async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      await tester.pumpWidget(host(c));

      // Locked: total, variance, reference, charged all masked (4 placeholders).
      expect(find.text(kMaskedAmountText), findsNWidgets(4));
      for (final leaked in ['195.00', '+90.00', '255.00', '300.00']) {
        expect(find.text(leaked), findsNothing, reason: 'leaked $leaked');
      }
      // Not sensitive: product, customer/invoice, quantity.
      expect(find.text('جبنة'), findsOneWidget);
      expect(find.textContaining('DINV-000007'), findsOneWidget);
      expect(find.text('2.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reveal-lock-button')));
      await tester.pump();
      await tester.pump();

      expect(find.text(kMaskedAmountText), findsNothing);
      expect(find.text('195.00'), findsOneWidget);
      expect(find.text('+90.00'), findsOneWidget);
      expect(find.text('255.00'), findsOneWidget);
      expect(find.text('300.00'), findsOneWidget);

      // Tapping the (now open) lock re-masks.
      await tester.tap(find.byKey(const ValueKey('reveal-lock-button')));
      await tester.pump();
      expect(find.text(kMaskedAmountText), findsNWidgets(4));

      c.dispose();
      await tester.pump(const Duration(seconds: 61)); // drain any pending timer
    });

    testWidgets('a failed auth leaves the page masked and tells the user', (tester) async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.failed]));
      await tester.pumpWidget(host(c));

      await tester.tap(find.byKey(const ValueKey('reveal-lock-button')));
      await tester.pump();
      await tester.pump();

      expect(find.text(kMaskedAmountText), findsNWidgets(4));
      expect(find.textContaining('لم يتم التحقق'), findsOneWidget);
      c.dispose();
    });

    testWidgets('tapping a masked figure itself also starts the reveal', (tester) async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.success]));
      await tester.pumpWidget(host(c));

      await tester.tap(find.text(kMaskedAmountText).first);
      await tester.pump();
      await tester.pump();

      expect(c.isRevealed, isTrue);
      c.dispose();
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('no screen lock on the device: reveals AND shows the unprotected-device notice', (tester) async {
      final c = SensitiveRevealController(FakeAuthenticator([DeviceAuthOutcome.unavailable]));
      await tester.pumpWidget(host(c));

      await tester.tap(find.byKey(const ValueKey('reveal-lock-button')));
      await tester.pump();
      await tester.pump();

      expect(find.text('جهازك غير محمي بقفل'), findsOneWidget);
      expect(c.isRevealed, isTrue);
      await tester.tap(find.text('حسنًا'));
      await tester.pump();
      expect(find.text('195.00'), findsOneWidget);
      c.dispose();
      await tester.pump(const Duration(seconds: 61));
    });
  });
}
