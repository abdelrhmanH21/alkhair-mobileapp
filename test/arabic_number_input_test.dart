import 'package:alkhair_mobileapp/core/network/api_client.dart';
import 'package:alkhair_mobileapp/core/utils/number_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Arabic-Indic (٠-٩) / Persian (۰-۹) digits are accepted everywhere a
/// number is typed, and everything that leaves the app is Latin.
void main() {
  group('normalizeDigits / normalizeNumericInput', () {
    test('Arabic-Indic and Persian digits → Latin', () {
      expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });

    test('normalizeDigits leaves letters and separators alone (safe on search text)', () {
      expect(normalizeDigits('أحمد ٠١٢٢، القاهرة'), 'أحمد 0122، القاهرة');
    });

    test('numeric fields: ٫ and ، → ".", ٬ and bidi marks removed', () {
      expect(normalizeNumericInput('١٢٫٥'), '12.5');
      expect(normalizeNumericInput('٣،٧٥'), '3.75');
      expect(normalizeNumericInput('١٬٢٥٠٫٥'), '1250.5');
      expect(normalizeNumericInput('‏٤٥'), '45');
    });
  });

  group('parseNumber', () {
    test('parses Latin, Arabic-Indic, Persian and mixed input', () {
      expect(parseNumber('12.5'), 12.5);
      expect(parseNumber('١٢٫٥'), 12.5);
      expect(parseNumber('۱۲۳'), 123.0);
      expect(parseNumber(' ١٬٠٠٠ '), 1000.0);
      expect(parseNumber('-٥'), -5.0);
    });

    test('blank / invalid / non-finite → null', () {
      expect(parseNumber(null), isNull);
      expect(parseNumber(''), isNull);
      expect(parseNumber('   '), isNull);
      expect(parseNumber('abc'), isNull);
      expect(parseNumber('NaN'), isNull);
      expect(parseNumber('Infinity'), isNull);
    });

    test('double.tryParse alone misparses Arabic digits (what this fixes)', () {
      expect(double.tryParse('١٢٫٥'), isNull);
    });
  });

  group('ArabicNumberInputFormatter', () {
    const f = ArabicNumberInputFormatter();
    TextEditingValue apply(String text, int caret) => f.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: caret)),
        );

    test('rewrites typed/pasted Arabic digits and keeps the caret in place', () {
      final v = apply('١٢٫٥', 4);
      expect(v.text, '12.5');
      expect(v.selection.baseOffset, 4);
    });

    test('caret shifts left when a removed thousands separator was before it', () {
      final v = apply('١٬٢٣', 3); // caret after "٢"
      expect(v.text, '123');
      expect(v.selection.baseOffset, 2);
    });

    test('Latin input passes through untouched (same instance)', () {
      const value = TextEditingValue(text: '42.5', selection: TextSelection.collapsed(offset: 4));
      expect(identical(f.formatEditUpdate(TextEditingValue.empty, value), value), isTrue);
    });

    testWidgets('a numeric TextField accepts Arabic digits end-to-end', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: numericInputFormatters,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '٢٥٠٫٧٥');
      expect(ctrl.text, '250.75');
      expect(parseNumber(ctrl.text), 250.75);
    });

    testWidgets('chained before a Latin-only allow-list, Arabic digits are no longer rejected', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: ctrl,
            inputFormatters: [
              const ArabicNumberInputFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
            ],
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '١٢٫٥');
      expect(ctrl.text, '12.5');
    });
  });

  group('normalizeNumericPayload / DigitNormalizingInterceptor', () {
    test('only whole numeric values are rewritten; free text and passwords never', () {
      final out = normalizeNumericPayload({
        'cash_amount': '١٢٫٥',
        'phone': '٠١٢٢٣٨٨٩٦٦٤',
        'notes': 'ملاحظة ١٢٣ جنيه',
        'password': '١٢٣٤',
        'items': [
          {'qty': '٣', 'note': 'كرتونة ٢'},
        ],
        'count': 7,
        'latin': '1,250',
      });
      expect(out, {
        'cash_amount': '12.5',
        'phone': '01223889664',
        'notes': 'ملاحظة ١٢٣ جنيه',
        'password': '١٢٣٤',
        'items': [
          {'qty': '3', 'note': 'كرتونة ٢'},
        ],
        'count': 7,
        'latin': '1,250',
      });
    });

    test('the interceptor normalizes JSON bodies, form fields and search query params', () {
      final options = RequestOptions(
        path: '/x',
        data: {'amount': '٤٥٫٥', 'notes': 'دفعة ٥'},
        queryParameters: {'search': 'أحمد ٠١٢٢', 'page': 2},
      );
      RequestOptions? sent;
      DigitNormalizingInterceptor().onRequest(options, _CapturingHandler((o) => sent = o));
      expect(sent!.data, {'amount': '45.5', 'notes': 'دفعة ٥'});
      expect(sent!.queryParameters, {'search': 'أحمد 0122', 'page': 2});

      final form = FormData.fromMap({'amount': '١٠٠', 'description': 'بنزين ٢ لتر'});
      DigitNormalizingInterceptor().onRequest(RequestOptions(path: '/y', data: form), _CapturingHandler((o) => sent = o));
      final fields = Map.fromEntries((sent!.data as FormData).fields);
      expect(fields, {'amount': '100', 'description': 'بنزين ٢ لتر'});
    });
  });
}

class _CapturingHandler extends RequestInterceptorHandler {
  final void Function(RequestOptions) onNext;
  _CapturingHandler(this.onNext);
  @override
  void next(RequestOptions requestOptions) => onNext(requestOptions);
}
