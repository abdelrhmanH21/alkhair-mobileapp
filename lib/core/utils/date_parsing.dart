/// Laravel/Carbon always serializes Eloquent model dates as UTC with a
/// trailing 'Z' in JSON responses (`Illuminate\Database\Eloquent\Concerns\
/// HasAttributes::serializeDate()`), regardless of the backend's own
/// `app.timezone` ('Africa/Cairo') — that config only affects how `now()`/
/// Carbon compute and store wall-clock values server-side, not how dates
/// are serialized over the API wire. Confirmed live: a real Sale's
/// `created_at` is stored as Cairo wall-clock `2026-05-08 05:50:27` but the
/// API serializes it as `2026-05-08T02:50:27.000000Z`.
///
/// `DateTime.parse`/`tryParse` on a 'Z'-suffixed string correctly tags the
/// result `isUtc == true`, but that alone does NOT convert it to the
/// device's local time — formatting it directly (e.g. via `intl`'s
/// `DateFormat`) prints the raw UTC hour/day fields verbatim. Nothing
/// converts it to local time unless `.toLocal()` is called explicitly.
/// Every backend-date parse site in this app used to skip that call, which
/// is why receipts/reports showed a time visibly behind real Cairo local
/// time (by Cairo's current UTC offset, e.g. 3 hours during EEST). Always
/// parse backend timestamps through these helpers instead of a bare
/// `DateTime.parse`/`tryParse`.
DateTime? tryParseServerDateTime(String? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// Same as [tryParseServerDateTime], but never null — falls back to
/// [fallback] (or the current local time) when [raw] is missing/unparsable,
/// matching the `DateTime.tryParse(x) ?? DateTime.now()` pattern this
/// replaces across the app's data models.
DateTime parseServerDateTime(String? raw, {DateTime? fallback}) {
  return tryParseServerDateTime(raw) ?? fallback ?? DateTime.now();
}
