import 'package:dau_shared/dau_shared.dart';

/// The live-score calculation, moved from the client to the server
/// (DESIGN-database-rules-phase4.md, M5).
///
/// Tippers submit the score they see as the game goes on. Every submission is a
/// `history` entry under `Stats/{comp}/live_scores_backend_v1/{game}/history`.
/// The scoring worker reads a `current` snapshot beside it. Until now the client
/// wrote that snapshot from its own idea of the list; the R2 client writes
/// `history` only, and this derives `current` from it.
///
/// The rule is the one the client has always applied, nothing cleverer:
/// - each team keeps its **three most recent** submissions;
/// - the displayed score for a team is its **latest** submission;
/// - the snapshot's time and tipper are those of the latest submission of either
///   team, and its completion flag is always false (only an official score
///   completes a game);
/// - an official score, when there is one, overrides all of it (the caller's
///   business: see `runLiveScoreAggregation`).

/// One `history` entry, read leniently.
class LiveScoreEntry implements Comparable<LiveScoreEntry> {
  const LiveScoreEntry({
    required this.key,
    required this.micros,
    required this.tipperId,
    required this.team,
    required this.score,
    required this.gameComplete,
  });

  /// The entry's key in `history`. Breaks a tie between equal times, so the
  /// order is always the same however the entries are delivered.
  final String key;

  /// When it was submitted, in microseconds since the epoch (UTC).
  final int micros;

  final String tipperId;
  final ScoringTeam team;
  final int score;

  /// The flag as found in the entry (or in a `current` snapshot being compared).
  /// **Never written back as true**: a game is completed by its official score
  /// alone, so [toJson] and the aggregate's snapshot always say `false`, whatever
  /// a legacy client left in `history`.
  final bool gameComplete;

  /// The earliest instant microseconds since the epoch can mean here (year
  /// 2001). A `t` of at least this is read as microseconds.
  static const int _plausibleMicros = 1000000000000000;

  /// Milliseconds since the epoch, for `t` as the R2 rules require it: the
  /// database's own server timestamp (`t === now`), the one time a client cannot
  /// choose. From year 2001 up to (not including) the microsecond range; a
  /// number in seconds is smaller and is not a plausible `t`.
  static const int _plausibleMillis = 1000000000000;
  static const int _implausibleMillis = 100000000000000;

  /// Reads an entry, or returns null if it cannot be used. The time comes from,
  /// in this order:
  ///
  /// 1. a numeric `t`: the database's server timestamp in milliseconds (the R2
  ///    client's field, which the R2 rules force to equal the server's `now`), or
  ///    microseconds since the epoch;
  /// 2. the legacy `submittedTimeUTC` text (the 1.4.x client's field, from the
  ///    client's own clock);
  /// 3. the push key itself, which the client builds as `{micros}-{team}`.
  static LiveScoreEntry? tryParse(String key, Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final micros = _micros(key, raw);
    final teamName = raw['scoreTeam'];
    final tipperId = raw['tipperID'];
    final score = _int(raw['interimScore']);
    if (micros == null ||
        teamName is! String ||
        tipperId is! String ||
        tipperId.isEmpty ||
        score == null) {
      return null;
    }
    final team = ScoringTeam.values.where((t) => t.name == teamName);
    if (team.isEmpty) {
      return null;
    }
    return LiveScoreEntry(
      key: key,
      micros: micros,
      tipperId: tipperId,
      team: team.first,
      score: score,
      gameComplete: raw['gameComplete'] == true,
    );
  }

  static int? _micros(String key, Map raw) {
    final t = raw['t'];
    if (t is num) {
      final value = t.toInt();
      if (value >= _plausibleMicros) {
        return value;
      }
      if (value >= _plausibleMillis && value < _implausibleMillis) {
        return value * 1000;
      }
    }
    final text = raw['submittedTimeUTC'];
    if (text is String) {
      final parsed = DateTime.tryParse(text);
      if (parsed != null) {
        return parsed.toUtc().microsecondsSinceEpoch;
      }
    }
    final fromKey = RegExp(r'^(\d{15,17})-').firstMatch(key);
    if (fromKey != null) {
      return int.parse(fromKey.group(1)!);
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// The entry as the snapshot's `crowdSourcedScores` carries it: the client's
  /// own `CrowdSourcedScore.toJson()` shape, which the scoring worker parses.
  Map<String, Object?> toJson() => <String, Object?>{
    'submittedTimeUTC': DateTime.fromMicrosecondsSinceEpoch(
      micros,
      isUtc: true,
    ).toIso8601String(),
    'tipperID': tipperId,
    'scoreTeam': team.name,
    'interimScore': score,
    'gameComplete': false,
  };

  @override
  int compareTo(LiveScoreEntry other) {
    final byTime = micros.compareTo(other.micros);
    return byTime != 0 ? byTime : key.compareTo(other.key);
  }
}

/// How many submissions each team keeps.
const int liveScoresKeptPerTeam = 3;

/// What `history` comes to.
class LiveScoreAggregate {
  const LiveScoreAggregate({
    required this.kept,
    required this.basedOnCount,
    required this.ignored,
  });

  /// The submissions kept: the three most recent of each team, oldest first.
  final List<LiveScoreEntry> kept;

  /// How many usable entries `history` held. It only grows while games are
  /// being scored, so it says which of two computations saw more.
  final int basedOnCount;

  /// How many entries could not be read.
  final int ignored;

  bool get isEmpty => kept.isEmpty;

  LiveScoreEntry? get latest => kept.isEmpty ? null : kept.last;

  LiveScoreEntry? _latestFor(ScoringTeam team) {
    for (final entry in kept.reversed) {
      if (entry.team == team) {
        return entry;
      }
    }
    return null;
  }

  /// The `current` snapshot, in the shape the client has always written (plus
  /// `basedOnCount`, which a legacy client's write leaves out). Null if there
  /// is nothing to show.
  Map<String, Object?>? get snapshot {
    final latest = this.latest;
    if (latest == null) {
      return null;
    }
    return <String, Object?>{
      'homeInterimScore': ?_latestFor(ScoringTeam.home)?.score,
      'awayInterimScore': ?_latestFor(ScoringTeam.away)?.score,
      'submittedTimeUTC': latest.toJson()['submittedTimeUTC'],
      'tipperID': latest.tipperId,
      'gameComplete': false,
      'crowdSourcedScores': <Map<String, Object?>>[
        for (final entry in kept) entry.toJson(),
      ],
      'basedOnCount': basedOnCount,
    };
  }
}

/// Derives the snapshot from a game's `history` node, whatever order its entries
/// arrive in and however often the same computation is run.
LiveScoreAggregate computeLiveScoreAggregate(Object? history) {
  final entries = <LiveScoreEntry>[];
  var ignored = 0;
  if (history is Map) {
    for (final raw in history.entries) {
      final entry = LiveScoreEntry.tryParse(raw.key.toString(), raw.value);
      if (entry == null) {
        ignored += 1;
      } else {
        entries.add(entry);
      }
    }
  }
  entries.sort();

  final kept = <LiveScoreEntry>[];
  for (final team in ScoringTeam.values) {
    final forTeam = entries.where((e) => e.team == team).toList();
    kept.addAll(
      forTeam.length > liveScoresKeptPerTeam
          ? forTeam.sublist(forTeam.length - liveScoresKeptPerTeam)
          : forTeam,
    );
  }
  kept.sort();
  return LiveScoreAggregate(
    kept: kept,
    basedOnCount: entries.length,
    ignored: ignored,
  );
}

/// How two snapshots differ, in words that name no one: an empty list means they
/// show the same game. `basedOnCount` and the order of the list are not
/// differences, and neither is how a time is spelled.
List<String> liveScoreDifferences(
  Object? actual,
  Map<String, Object?> expected,
) {
  if (actual is! Map) {
    return <String>['no current snapshot'];
  }
  final differences = <String>[];
  for (final field in const <String>[
    'homeInterimScore',
    'awayInterimScore',
    'tipperID',
  ]) {
    if (actual[field] != expected[field]) {
      differences.add(
        '$field: ${actual[field]} but expected ${expected[field]}',
      );
    }
  }
  // A snapshot that does not say it is complete is not complete.
  if ((actual['gameComplete'] == true) != (expected['gameComplete'] == true)) {
    differences.add('gameComplete differs');
  }
  final actualTime = _timeOf(actual['submittedTimeUTC']);
  final expectedTime = _timeOf(expected['submittedTimeUTC']);
  if (actualTime != expectedTime) {
    differences.add('submittedTimeUTC differs');
  }

  final actualScores = _canonicalScores(actual['crowdSourcedScores']);
  final expectedScores = _canonicalScores(expected['crowdSourcedScores']);
  final onlyActual = actualScores.where((s) => !expectedScores.contains(s));
  final onlyExpected = expectedScores.where((s) => !actualScores.contains(s));
  if (onlyActual.isNotEmpty || onlyExpected.isNotEmpty) {
    differences.add(
      'crowdSourcedScores: ${onlyActual.length} not expected, '
      '${onlyExpected.length} missing',
    );
  }
  return differences;
}

int? _timeOf(Object? text) => text is String
    ? DateTime.tryParse(text)?.toUtc().microsecondsSinceEpoch
    : null;

List<String> _canonicalScores(Object? raw) {
  final values = raw is List
      ? raw
      : raw is Map
      ? raw.values.toList()
      : const <Object?>[];
  final entries = <LiveScoreEntry>[];
  for (final value in values) {
    final entry = LiveScoreEntry.tryParse('-', value);
    if (entry != null) {
      entries.add(entry);
    }
  }
  entries.sort();
  return <String>[
    for (final e in entries)
      '${e.micros}|${e.team.name}|${e.tipperId}|${e.score}|${e.gameComplete}',
  ];
}
