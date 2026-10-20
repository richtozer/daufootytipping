/// The key of a game's kickoff as the fixture feed writes it, for example
/// `2026-03-01 02:15:00Z`.
const String dateUtcKey = 'DateUtc';

/// The key of the same instant as UTC milliseconds since the epoch. It is
/// written in the same database update as [dateUtcKey] by every writer, so the
/// database rules can compare it with the time without parsing a string.
const String dateUtcEpochMsKey = 'DateUtcEpochMs';

final RegExp _storedFormat = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?Z$',
);

/// The kickoff time [dateUtc] names, in UTC milliseconds since the epoch.
///
/// Reads the stored format, `yyyy-MM-dd HH:mm:ssZ`, and the same with a `T`
/// between date and time or milliseconds after the seconds, which
/// `DateTime.parse` and the rest of the app also accept. Anything else throws a
/// [FormatException]: a time with no `Z` (not stated as UTC), another offset,
/// and dates that do not exist (30 February). A game must never be written with
/// a kickoff the rules cannot read, so there is no lenient fallback.
int kickoffEpochMsFromDateUtc(String dateUtc) {
  final match = _storedFormat.firstMatch(dateUtc);
  if (match == null) {
    throw FormatException(
      'DateUtc must look like "2026-03-01 02:15:00Z"',
      dateUtc,
    );
  }
  final parts = <int>[
    for (var group = 1; group <= 6; group++) int.parse(match.group(group)!),
  ];
  final fraction = match.group(7);
  final milliseconds = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0'));
  final parsed = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
    milliseconds,
  );
  // DateTime.utc rolls an impossible date over (30 February becomes 2 March),
  // so check that nothing moved.
  final unchanged =
      parsed.year == parts[0] &&
      parsed.month == parts[1] &&
      parsed.day == parts[2] &&
      parsed.hour == parts[3] &&
      parsed.minute == parts[4] &&
      parsed.second == parts[5];
  if (!unchanged) {
    throw FormatException('DateUtc is not a real date and time', dateUtc);
  }
  return parsed.millisecondsSinceEpoch;
}

/// [kickoff] in the stored `DateUtc` format.
String dateUtcFromDateTime(DateTime kickoff) {
  final utc = kickoff.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final year = utc.year.toString().padLeft(4, '0');
  return '$year-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}
