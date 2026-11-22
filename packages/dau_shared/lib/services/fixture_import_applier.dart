import '../models/daucomp.dart';
import '../models/dauround.dart';
import '../models/game.dart';
import '../models/league.dart';
import 'combined_rounds_service.dart';
import 'kickoff_time.dart';
import 'tipping_policy.dart';

class GameUpdate {
  final String dbkey;
  final String league; // 'nrl' or 'afl'
  final Map<String, dynamic> attributes;

  GameUpdate({
    required this.dbkey,
    required this.league,
    required this.attributes,
  });
}

class FixtureImportApplier {
  const FixtureImportApplier();

  static const Set<String> _persistedGameAttributeKeys = <String>{
    'League',
    'HomeTeam',
    'AwayTeam',
    'Location',
    'DateUtc',
    'RoundNumber',
    'MatchNumber',
    'HomeTeamScore',
    'AwayTeamScore',
  };

  List<GameUpdate> buildGameUpdates(
    List<dynamic> nrlGames,
    List<dynamic> aflGames, {
    Map<String, dynamic> existingGames = const <String, dynamic>{},
    DateTime? now,
    void Function(String message)? log,
  }) {
    final updates = <GameUpdate>[];

    void addUpdates(List<dynamic> games, String league) {
      for (final gamejson in games.cast<Map<dynamic, dynamic>>()) {
        final dbkey =
            '$league-${gamejson['RoundNumber'].toString().padLeft(2, '0')}-${gamejson['MatchNumber'].toString().padLeft(3, '0')}';
        final attributes = Map<String, dynamic>.fromEntries(
          gamejson.entries
              .where(
                (entry) =>
                    _persistedGameAttributeKeys.contains(entry.key.toString()),
              )
              .map(
                (entry) => MapEntry<String, dynamic>(
                  entry.key.toString(),
                  entry.value,
                ),
              ),
        );
        _freezeKickoffIfNeeded(
          dbkey: dbkey,
          attributes: attributes,
          existingGame: existingGames[dbkey],
          now: now,
          log: log,
        );
        _addKickoffEpoch(dbkey, attributes);
        updates.add(
          GameUpdate(dbkey: dbkey, league: league, attributes: attributes),
        );
      }
    }

    addUpdates(nrlGames, 'nrl');
    addUpdates(aflGames, 'afl');
    return updates;
  }

  void _freezeKickoffIfNeeded({
    required String dbkey,
    required Map<String, dynamic> attributes,
    required dynamic existingGame,
    required DateTime? now,
    required void Function(String message)? log,
  }) {
    if (existingGame is! Map) {
      return;
    }
    final existingDateUtc = existingGame[dateUtcKey];
    if (existingDateUtc is! String || existingDateUtc.isEmpty) {
      return;
    }
    final existingKickoffMs = _tryParseKickoffEpochMs(existingDateUtc);
    final isScored =
        existingGame['HomeTeamScore'] != null &&
        existingGame['AwayTeamScore'] != null;
    final nowMs = now?.toUtc().millisecondsSinceEpoch;
    final freezeHorizonMs = nowMs != null
        ? nowMs + maxTipGracePeriodSeconds * 1000
        : null;
    final isFrozenByTime =
        freezeHorizonMs != null &&
        existingKickoffMs != null &&
        existingKickoffMs <= freezeHorizonMs;
    if (!isScored && !isFrozenByTime) {
      return;
    }

    final incomingDateUtc = attributes[dateUtcKey];
    final incomingKickoffMs = incomingDateUtc is String
        ? _tryParseKickoffEpochMs(incomingDateUtc)
        : null;
    final kickoffChanged =
        incomingDateUtc != existingDateUtc &&
        (existingKickoffMs == null || incomingKickoffMs != existingKickoffMs);
    if (kickoffChanged) {
      final reason = isScored
          ? 'game already has an official score'
          : (nowMs != null &&
                existingKickoffMs != null &&
                existingKickoffMs <= nowMs)
          ? 'stored kickoff ($existingDateUtc) has already passed'
          : 'stored kickoff ($existingDateUtc) is within the ${maxTipGracePeriodSeconds}s grace window';
      log?.call(
        'Ignoring kickoff change for $dbkey ($incomingDateUtc -> kept $existingDateUtc) because $reason.',
      );
    }
    attributes[dateUtcKey] = existingDateUtc;
  }

  int? _tryParseKickoffEpochMs(String dateUtc) {
    try {
      return kickoffEpochMsFromDateUtc(dateUtc);
    } on FormatException {
      return DateTime.tryParse(dateUtc)?.toUtc().millisecondsSinceEpoch;
    }
  }

  /// Recalculates each round's `roundEndDate` from the post-freeze games and
  /// returns a map of DB array index (`round.dAUroundNumber - 1`) -> formatted
  /// UTC timestamp string for every round whose end date changed (or all rounds
  /// when [forceWriteAll] is true). Fully scored rounds keep their stored end
  /// capped at one second before the next round's start. Also updates
  /// `round.lastGameKickOffUTC` in memory.
  Map<int, String> recalculateRoundEndDates({
    required DAUComp comp,
    required List<GameUpdate> gameUpdates,
    Map<String, dynamic> existingGames = const <String, dynamic>{},
    List<DAURound>? roundsOverride,
    bool forceWriteAll = false,
  }) {
    final rounds = roundsOverride ?? comp.daurounds;
    if (rounds.isEmpty) {
      return const <int, String>{};
    }
    final sortedRounds = [...rounds]
      ..sort((a, b) => a.dAUroundNumber.compareTo(b.dAUroundNumber));

    final mergedByKey = <String, Map<String, dynamic>>{};
    existingGames.forEach((dbkey, raw) {
      if (raw is Map) {
        mergedByKey[dbkey] = Map<String, dynamic>.from(raw);
      }
    });
    for (final op in gameUpdates) {
      mergedByKey[op.dbkey] = <String, dynamic>{
        ...?mergedByKey[op.dbkey],
        ...op.attributes,
      };
    }

    final gamesByRoundNumber = <int, List<({DateTime kickoff, bool scored})>>{
      for (final round in sortedRounds) round.dAUroundNumber: [],
    };

    for (final entry in mergedByKey.entries) {
      final dbkey = entry.key;
      final data = entry.value;
      final league = _leagueFromGameEntry(dbkey, data);
      if (league == null) continue;
      final dateUtc = data[dateUtcKey];
      if (dateUtc is! String || dateUtc.isEmpty) continue;
      final kickoff = DateTime.tryParse(dateUtc)?.toUtc();
      if (kickoff == null) continue;

      final assignedRound = Game.roundForKickoff(
        kickoffUTC: kickoff,
        league: league,
        rounds: sortedRounds,
        aflCutoffUTC: comp.aflRegularCompEndDateUTC,
        nrlCutoffUTC: comp.nrlRegularCompEndDateUTC,
        boundFinalRoundByEndDate: false,
      );
      if (assignedRound == null) continue;

      final scored =
          data['HomeTeamScore'] != null && data['AwayTeamScore'] != null;
      gamesByRoundNumber[assignedRound.dAUroundNumber]?.add((
        kickoff: kickoff,
        scored: scored,
      ));
    }

    final changedEnds = <int, String>{};
    for (var i = 0; i < sortedRounds.length; i++) {
      final round = sortedRounds[i];
      final assigned = gamesByRoundNumber[round.dAUroundNumber] ?? const [];

      DateTime newEnd;
      if (!forceWriteAll &&
          assigned.isNotEmpty &&
          assigned.every((g) => g.scored)) {
        newEnd = round.lastGameKickOffUTC.toUtc();
      } else if (assigned.isEmpty) {
        newEnd = round.getRoundStartDate().toUtc();
      } else {
        var maxKickoff = assigned.first.kickoff;
        for (final g in assigned.skip(1)) {
          if (g.kickoff.isAfter(maxKickoff)) {
            maxKickoff = g.kickoff;
          }
        }
        newEnd = maxKickoff.add(const Duration(hours: 3));
      }

      if (assigned.isNotEmpty && i + 1 < sortedRounds.length) {
        final nextStart = sortedRounds[i + 1].getRoundStartDate().toUtc();
        final cap = nextStart.subtract(const Duration(seconds: 1));
        if (newEnd.isAfter(cap)) {
          newEnd = cap;
        }
      }

      final newEndStr = dateUtcFromDateTime(newEnd);
      final currentEndStr = dateUtcFromDateTime(round.lastGameKickOffUTC);
      if (forceWriteAll || newEndStr != currentEndStr) {
        round.lastGameKickOffUTC = newEnd;
        changedEnds[round.dAUroundNumber - 1] = newEndStr;
      }
    }

    return changedEnds;
  }

  League? _leagueFromGameEntry(String dbkey, Map<String, dynamic> data) {
    final leagueRaw = data['League']?.toString().toLowerCase();
    if (leagueRaw == 'nrl' || dbkey.startsWith('nrl')) {
      return League.nrl;
    }
    if (leagueRaw == 'afl' || dbkey.startsWith('afl')) {
      return League.afl;
    }
    return null;
  }

  /// Writes the numeric kickoff beside `DateUtc`, in the same attribute set so
  /// that every writer puts them in the same database update. A `DateUtc` that
  /// cannot be read fails the whole import, naming the game, instead of writing
  /// a game whose kickoff the rules cannot use.
  void _addKickoffEpoch(String dbkey, Map<String, dynamic> attributes) {
    if (!attributes.containsKey(dateUtcKey)) {
      return;
    }
    final dateUtc = attributes[dateUtcKey];
    if (dateUtc is! String) {
      throw FormatException(
        'Game $dbkey has a DateUtc that is not text',
        dateUtc?.toString(),
      );
    }
    try {
      attributes[dateUtcEpochMsKey] = kickoffEpochMsFromDateUtc(dateUtc);
    } on FormatException catch (error) {
      throw FormatException(
        'Game $dbkey has an unusable DateUtc: ${error.message}',
        dateUtc,
      );
    }
  }

  void tagGamesWithLeagueInPlace(List<dynamic> games, String league) {
    for (final game in games) {
      if (game is Map) {
        game['league'] = league;
      }
    }
  }

  /// Builds the comp's rounds on its first download, when it has none. A
  /// league with no cutoff yet gets one from its feed, set on [comp], and the
  /// rounds hold only the games inside the cutoffs. Later downloads leave the
  /// cutoffs to the administrator.
  List<DAURound>? computeCombinedRoundsIfMissing(
    DAUComp comp,
    List<dynamic> allGames,
  ) {
    if (comp.daurounds.isNotEmpty) return null;
    List<dynamic> gamesOf(String league) => [
      for (final game in allGames)
        if (game is Map && game['league'] == league) game,
    ];
    comp.nrlRegularCompEndDateUTC ??= regularSeasonCutoffUTC(gamesOf('nrl'));
    comp.aflRegularCompEndDateUTC ??= regularSeasonCutoffUTC(gamesOf('afl'));
    final regularSeason = allGames.where((game) {
      if (game is! Map) return true;
      final cutoff = switch (game['league']) {
        'nrl' => comp.nrlRegularCompEndDateUTC,
        'afl' => comp.aflRegularCompEndDateUTC,
        _ => null,
      };
      final kickoff = DateTime.tryParse('${game['DateUtc']}');
      return cutoff == null || kickoff == null || !kickoff.isAfter(cutoff);
    }).toList();
    return CombinedRoundsService().buildCombinedRounds(regularSeason);
  }

  /// When one league's regular season ends, read from its fixture feed.
  ///
  /// Early in the year a feed lists its finals with placeholder teams such as
  /// "1st" or "Winner of QF1", each of which plays in one round only. The
  /// season ends at 0:00 UTC on the day the first round made up entirely of
  /// placeholder games starts. Regular-season kickoffs are often parked on one
  /// day until they are set, so the finals' start is the safer boundary. A
  /// feed with no such round ends the day after its last game. Returns null
  /// when no team plays in more than one round, as nothing can be told apart.
  DateTime? regularSeasonCutoffUTC(List<dynamic> leagueGames) {
    final games = [
      for (final game in leagueGames)
        if (game is Map &&
            game['RoundNumber'] is int &&
            DateTime.tryParse('${game['DateUtc']}') != null)
          game,
    ];
    final roundsByTeam = <Object?, Set<int>>{};
    for (final game in games) {
      for (final team in [game['HomeTeam'], game['AwayTeam']]) {
        (roundsByTeam[team] ??= {}).add(game['RoundNumber'] as int);
      }
    }
    if (roundsByTeam.values.every((rounds) => rounds.length < 2)) return null;
    bool isPlaceholderGame(Map game) =>
        game['HomeTeam'] == game['AwayTeam'] ||
        [
          game['HomeTeam'],
          game['AwayTeam'],
        ].every((team) => (roundsByTeam[team]?.length ?? 0) == 1);
    DateTime kickoff(Map game) => DateTime.parse('${game['DateUtc']}').toUtc();
    DateTime day(DateTime time) =>
        DateTime.utc(time.year, time.month, time.day);

    final roundNumbers = {
      for (final game in games) game['RoundNumber'] as int,
    }.toList()..sort();
    for (final roundNumber in roundNumbers) {
      final round = [
        for (final game in games)
          if (game['RoundNumber'] == roundNumber) game,
      ];
      if (round.every(isPlaceholderGame)) {
        return day(round.map(kickoff).reduce((a, b) => a.isBefore(b) ? a : b));
      }
    }
    final lastKickoff = games
        .map(kickoff)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return day(lastKickoff).add(const Duration(days: 1));
  }
}
