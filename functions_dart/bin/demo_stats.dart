// Offline demo enrichment using the same models/calculators as the backend.
import 'dart:convert';
import 'dart:io';
import 'package:dau_shared/dau_shared.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: dart run bin/demo_stats.dart competition.json UTC-anchor',
    );
  }
  final file = File(args[0]);
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final now = DateTime.parse(args[1]).toUtc();
  final compKey = data['AppConfig']['currentDAUComp'] as String;
  if (compKey != 'demo-celebrity-2026') {
    throw ArgumentError('Not a demo dataset');
  }
  final rawComp = Map<String, dynamic>.from(data['AllDAUComps'][compKey]);
  final rounds = <DAURound>[
    for (final (index, raw) in (rawComp['combinedRounds2'] as List).indexed)
      DAURound.fromJson(Map<String, dynamic>.from(raw), index + 1),
  ];
  final comp = DAUComp.fromJson(rawComp, compKey, rounds);
  final teams = <String, Team>{
    for (final entry in (data['Teams'] as Map).entries)
      entry.key: Team.fromJson(
        Map<String, dynamic>.from(entry.value),
        entry.key,
      ),
  };
  final stats = Map<String, dynamic>.from(data['Stats'][compKey]);
  final games = <String, Game>{};
  for (final entry in (data['DAUCompsGames'][compKey] as Map).entries) {
    final key = entry.key as String;
    final raw = Map<String, dynamic>.from(entry.value);
    final league = key.substring(0, 3);
    final game = Game.fromJson(
      key,
      raw,
      teams['$league-${raw['HomeTeam']}']!,
      teams['$league-${raw['AwayTeam']}']!,
    );
    game.scoring = Scoring(
      homeTeamScore: raw['HomeTeamScore'],
      awayTeamScore: raw['AwayTeamScore'],
    );
    games[key] = game;
    final matching = rounds.where(game.isGameInRound).toList();
    if (matching.length != 1) {
      throw StateError('Game $key must belong to exactly one round');
    }
    // DAURound's default games list is const; populate with a new list.
    matching.single.games = [...matching.single.games, game];
  }
  final tippers = <Tipper>[
    for (final entry in (data['AllTippers'] as Map).entries)
      Tipper.fromJson(Map<String, dynamic>.from(entry.value), entry.key)
        ..compsPaidFor = [comp],
  ];
  final tipsByTipper = <String, Map<String, Tip>>{};
  for (final tipper in tippers) {
    final rawTips = data['AllTips'][compKey][tipper.dbkey] as Map;
    tipsByTipper[tipper.dbkey!] = {
      for (final entry in rawTips.entries)
        entry.key: Tip.fromJson(
          entry.value,
          entry.key,
          tipper,
          games[entry.key]!,
        ),
    };
    // Match backend defaults: missing tips on started games become Away.
    for (final game in games.values.where(
      (g) => !now.isBefore(g.startTimeUTC),
    )) {
      tipsByTipper[tipper.dbkey]!.putIfAbsent(
        game.dbkey,
        () => Tip(
          game: game,
          tipper: tipper,
          tip: GameResult.d,
          submittedTimeUTC: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
  }
  stats['round_stats_backend_v1'] = {
    for (final round in rounds)
      '${round.dAUroundNumber}': {
        for (final tipper in tippers)
          tipper.dbkey!: ScoringCalculator.calculateRoundStatsForTipper(
            roundNumber: round.dAUroundNumber,
            games: round.games,
            tipsByGameKey: tipsByTipper[tipper.dbkey]!,
            now: now,
          ).toJson(),
      },
  };
  stats['game_stats_backend_v1'] = {
    'paid': {
      for (final game in games.values.where(
        (g) => !now.isBefore(g.startTimeUTC),
      ))
        game.dbkey: ScoringCalculator.calculateGameStatsEntry(
          cohortTippers: tippers,
          tipsForCohort: [
            for (final tipper in tippers)
              tipsByTipper[tipper.dbkey]![game.dbkey],
          ],
          league: game.league,
        ).toJson(),
    },
  };
  data['Stats'][compKey] = stats;
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
  );
  stdout.writeln(
    'Calculated ${rounds.length} rounds and ${games.length} games with shared scoring code.',
  );
}
