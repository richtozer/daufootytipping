import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/rounds_linking_service.dart';

void main() {
  group('RoundsLinkingService', () {
    Team nrlTeam(String id) => Team(dbkey: 'nrl-$id', name: 'NRL $id', league: League.nrl);
    Team aflTeam(String id) => Team(dbkey: 'afl-$id', name: 'AFL $id', league: League.afl);

    Game finishedNRL(String key, int round) => Game(
          dbkey: key,
          league: League.nrl,
          homeTeam: nrlTeam('h'),
          awayTeam: nrlTeam('a'),
          location: 'X',
          startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
          fixtureRoundNumber: round,
          fixtureMatchNumber: 1,
          scoring: Scoring(homeTeamScore: 10, awayTeamScore: 8),
        );
    Game finishedAFL(String key, int round) => Game(
          dbkey: key,
          league: League.afl,
          homeTeam: aflTeam('h'),
          awayTeam: aflTeam('a'),
          location: 'Y',
          startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 6)),
          fixtureRoundNumber: round,
          fixtureMatchNumber: 1,
          scoring: Scoring(homeTeamScore: 12, awayTeamScore: 3),
        );

    test('finalizes rounds, sets state/counts, and computes unassigned with cutoffs', () {
      final svc = const RoundsLinkingService();
      final now = DateTime.now().toUtc();

      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 2)),
        lastGameKickOffUTC: now.subtract(const Duration(days: 1)),
        games: [
          finishedNRL('nrl-01-001', 1),
          finishedAFL('afl-01-001', 1),
        ],
      );

      // All games in r1 are finished => state should be allGamesEnded
      final extraNrl = Game(
        dbkey: 'nrl-99-001',
        league: League.nrl,
        homeTeam: nrlTeam('h2'),
        awayTeam: nrlTeam('a2'),
        location: 'Z',
        startTimeUTC: now.add(const Duration(days: 1)),
        fixtureRoundNumber: 99,
        fixtureMatchNumber: 1,
      );
      final extraAflBeyondCutoff = Game(
        dbkey: 'afl-99-001',
        league: League.afl,
        homeTeam: aflTeam('h2'),
        awayTeam: aflTeam('a2'),
        location: 'Q',
        startTimeUTC: now.add(const Duration(days: 5)),
        fixtureRoundNumber: 99,
        fixtureMatchNumber: 1,
      );

      final allGames = <Game>[...r1.games, extraNrl, extraAflBeyondCutoff];

      final unassigned = svc.finalizeRoundsAndComputeUnassigned(
        rounds: [r1],
        allGames: allGames,
        nrlCutoff: now.add(const Duration(days: 3)), // keep extra NRL
        aflCutoff: now.add(const Duration(days: 2)), // drop extra AFL
      );

      expect(r1.roundState, RoundState.allGamesEnded);
      expect(r1.nrlGameCount, 1);
      expect(r1.aflGameCount, 1);

      // Only extraNrl should remain in unassigned after cutoff filtering
      expect(unassigned.map((g) => g.dbkey), contains('nrl-99-001'));
      expect(unassigned.map((g) => g.dbkey), isNot(contains('afl-99-001')));
    });

    test('round with mixed states becomes started (not all ended)', () {
      final svc = const RoundsLinkingService();
      final now = DateTime.now().toUtc();

      final futureNRL = Game(
        dbkey: 'nrl-future',
        league: League.nrl,
        homeTeam: nrlTeam('h'),
        awayTeam: nrlTeam('a'),
        location: 'X',
        startTimeUTC: now.add(const Duration(hours: 3)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
      );

      final r = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now.subtract(const Duration(days: 1)),
        lastGameKickOffUTC: now.add(const Duration(days: 1)),
        games: [finishedNRL('nrl-01-001', 1), futureNRL],
      );

      final unassigned = svc.finalizeRoundsAndComputeUnassigned(
        rounds: [r],
        allGames: [finishedNRL('nrl-01-001', 1), futureNRL],
      );

      expect(r.roundState, RoundState.started);
      expect(r.nrlGameCount + r.aflGameCount, 2);
      expect(unassigned, isEmpty);
    });
  });
}
