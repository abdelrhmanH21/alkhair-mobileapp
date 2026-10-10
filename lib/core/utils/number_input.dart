import 'package:flutter/services.dart';

/// Arabic-Indic / Persian digit + separator normalization for every numeric
/// field (amounts, quantities, prices, discounts, phones) and for search
/// queries.
///
/// The OS keypad decides which digits it shows (iOS follows the system
/// "Numbers" setting; Gboard/Samsung can be switched to Arabic numerals), and
/// pasted text can carry either script — so Arabic digits must never be
/// rejected or misparsed. Everything that leaves this app (validation,
/// storage, API calls) is Latin.

/// ٠-٩ (U+0660–0669) and ۰-۹ (U+06F0–06F9) → 0-9. Nothing else is touched,
/// so this is safe on free text such as a customer-search query.
String normalizeDigits(String input) {
  StringBuffer? out;
  for (var i = 0; i < input.length; i++) {
    final c = input.codeUnitAt(i);
    int? latin;
    if (c >= 0x0660 && c <= 0x0669) {
      latin = 0x30 + (c - 0x0660);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      latin = 0x30 + (c - 0x06F0);
    }
    if (latin != null) {
      out ??= StringBuffer(input.substring(0, i));
      out.writeCharCode(latin);
    } else {
      out?.writeCharCode(c);
    }
  }
  return out?.toString() ?? input;
}

/// Numeric-field normalization: [normalizeDigits] plus the Arabic decimal
/// separator ٫ (U+066B) and the Arabic comma ، (U+060C) → ".", the Arabic
/// thousands separator ٬ (U+066C) removed, and invisible bidi marks
/// (LRM/RLM/ALM, often carried along by a paste) removed. Only for fields
/// that hold a number — never on free text.
String normalizeNumericInput(String input) {
  final digits = normalizeDigits(input);
  StringBuffer? out;
  for (var i = 0; i < digits.length; i++) {
    final c = digits.codeUnitAt(i);
    final String? replacement = switch (c) {
      0x066B || 0x060C => '.',
      0x066C || 0x200E || 0x200F || 0x061C => '',
      _ => null,
    };
    if (replacement != null) {
      out ??= StringBuffer(digits.substring(0, i));
      out.write(replacement);
    } else {
      out?.writeCharCode(c);
    }
  }
  return out?.toString() ?? digits;
}

/// Parses a user-entered number written in Latin, Arabic-Indic or Persian
/// digits. Returns null for blank or non-numeric text (and for NaN/Infinity,
/// which double.tryParse would otherwise accept).
double? parseNumber(String? text) {
  if (text == null) return null;
  final normalized = normalizeNumericInput(text).trim();
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Rewrites Arabic-Indic/Persian digits and Arabic separators to their Latin
/// form as they are typed or pasted, keeping the caret where it was. Unlike
/// FilteringTextInputFormatter.digitsOnly it never rejects input, and it
/// doesn't change the keyboard — the field keeps its numeric keypad.
class ArabicNumberInputFormatter extends TextInputFormatter {
  const ArabicNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = normalizeNumericInput(newValue.text);
    if (text == newValue.text) return newValue;
    int mapOffset(int offset) => offset < 0
        ? offset
        : normalizeNumericInput(newValue.text.substring(0, offset.clamp(0, newValue.text.length))).length;
    return TextEditingValue(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: mapOffset(newValue.selection.baseOffset),
        extentOffset: mapOffset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}

/// The formatter list every numeric TextField/TextFormField uses.
const List<TextInputFormatter> numericInputFormatters = [ArabicNumberInputFormatter()];

final _hasArabicNumeric = RegExp('[٠-٩۰-۹٫٬،]');
final _numericLike = RegExp('^[\\s+\\-0-9٠-٩۰-۹.,٫٬،‎‏؜]+\$');
final _hasDigit = RegExp('[0-9٠-٩۰-۹]');

/// Keys whose values are sent exactly as typed, whatever they contain.
const _neverNormalizedKeys = {'password', 'password_confirmation', 'current_password', 'new_password', 'token'};

/// True when the WHOLE string is a number/phone in any digit script
/// ("١٢٫٥", "٠١٢٢٣٨٨٩٦٦٤") — never for free text ("ملاحظة ١٢٣ جنيه").
bool isNumericLike(String value) => _hasDigit.hasMatch(value) && _numericLike.hasMatch(value);

/// Outgoing-payload pass (the same rule as the backend's
/// NormalizeArabicDigits middleware): a string value that is numeric as a
/// whole and contains Arabic/Persian characters is rewritten to Latin;
/// everything else — free text, already-Latin values, passwords — is sent
/// untouched.
Object? normalizeNumericPayload(Object? value, [String? key]) {
  if (key != null && _neverNormalizedKeys.contains(key)) return value;
  if (value is String) {
    if (!_hasArabicNumeric.hasMatch(value) || !isNumericLike(value)) return value;
    return normalizeNumericInput(value).trim();
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, normalizeNumericPayload(v, k is String ? k : null)));
  }
  if (value is List) return value.map((v) => normalizeNumericPayload(v)).toList();
  return value;
}
