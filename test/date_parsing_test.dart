import 'package:flutter_test/flutter_test.dart';
import 'package:alkhair_mobileapp/core/utils/date_parsing.dart';

void main() {
  group('parseServerDateTime / tryParseServerDateTime', () {
    // Regression test: a real Sale's created_at is stored server-side as
    // Cairo wall-clock 2026-05-08 05:50:27, but Laravel always serializes
    // Eloquent dates as UTC over JSON — this is exactly what a real API
    // response looked like for it (confirmed via tinker).
    const utcJson = '2026-05-08T02:50:27.000000Z';

    test('converts to local time, not the raw UTC hour', () {
      final parsed = parseServerDateTime(utcJson);
      expect(parsed.isUtc, isFalse,
          reason: 'must be converted to local, not left tagged as UTC');
      // Round-trips back to the original Cairo wall-clock instant: local
      // fields must differ from the raw UTC fields whenever the device's
      // own UTC offset isn't exactly zero (true for any real Cairo phone).
      if (DateTime.now().timeZoneOffset != Duration.zero) {
        expect(parsed.hour, isNot(2),
            reason: 'formatting this without converting would show the '
                'wrong (UTC) hour instead of local time — the exact bug a '
                'real physical receipt showed');
      }
    });

    test('matches manual .toLocal() on the same instant', () {
      final viaHelper = parseServerDateTime(utcJson);
      final viaManual = DateTime.parse(utcJson).toLocal();
      expect(viaHelper, viaManual);
    });

    test('tryParseServerDateTime returns null for null input', () {
      expect(tryParseServerDateTime(null), isNull);
    });

    test('tryParseServerDateTime returns null for unparsable input', () {
      expect(tryParseServerDateTime('not a date'), isNull);
    });

    test('parseServerDateTime falls back to fallback, then DateTime.now()', () {
      final fallback = DateTime(2020, 1, 1);
      expect(parseServerDateTime(null, fallback: fallback), fallback);
      expect(parseServerDateTime(null).difference(DateTime.now()).inMinutes.abs(),
          lessThan(1));
    });
  });
}
