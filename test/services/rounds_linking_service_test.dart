import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/rounds_linking_service.dart';

void main() {
  group('RoundsLinkingService', () {
    Team nrlTeam(String id) =>
        Team(dbkey: 'nrl-$id', name: 'NRL $id', league: League.nrl);
    Team aflTeam(String id) =>
        Team(dbkey: 'afl-$id', name: 'AFL $id', league: League.afl);

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
        games: [finishedNRL('nrl-01-001', 1), finishedAFL('afl-01-001', 1)],
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

    group('computeSplitRoundGames', () {
      const svc = RoundsLinkingService();
      final now = DateTime.utc(2026, 3, 1, 0, 0);

      Game makeGame(
        String key,
        League league,
        int fixtureRound,
        DateTime kickoff, {
        Scoring? scoring,
      }) => Game(
        dbkey: key,
        league: league,
        homeTeam: league == League.nrl ? nrlTeam('h') : aflTeam('h'),
        awayTeam: league == League.nrl ? nrlTeam('a') : aflTeam('a'),
        location: 'X',
        startTimeUTC: kickoff,
        fixtureRoundNumber: fixtureRound,
        fixtureMatchNumber: 1,
        scoring: scoring,
      );

      test('flags a game moved earlier into previous DAU round', () {
        final earlyGame = makeGame(
          'nrl-02-001',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 2, 10, 0),
        );
        final home1 = makeGame(
          'nrl-02-002',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 8, 10, 0),
        );
        final home2 = makeGame(
          'nrl-02-003',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 9, 10, 0),
        );

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 3),
          games: [earlyGame],
        );
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          games: [home1, home2],
        );

        final split = svc.computeSplitRoundGames(rounds: [r1, r2], now: now);
        expect(split, hasLength(1));
        expect(split.single.game.dbkey, 'nrl-02-001');
        expect(split.single.assignedRoundNumber, 1);
        expect(split.single.homeRoundNumber, 2);
      });

      test('does not flag when whole league round sits in one DAU round', () {
        final g1 = makeGame(
          'afl-02-001',
          League.afl,
          2,
          DateTime.utc(2026, 3, 2),
        );
        final g2 = makeGame(
          'afl-02-002',
          League.afl,
          2,
          DateTime.utc(2026, 3, 3),
        );
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 4),
          games: [g1, g2],
        );
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          games: const [],
        );

        expect(svc.computeSplitRoundGames(rounds: [r1, r2], now: now), isEmpty);
      });

      test('ignores started games and games past league cutoff', () {
        final startedSplit = makeGame(
          'nrl-02-001',
          League.nrl,
          2,
          now.subtract(const Duration(hours: 1)),
        );
        final pastCutoffSplit = makeGame(
          'nrl-02-004',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 20),
        );
        final home1 = makeGame(
          'nrl-02-002',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 8),
        );
        final home2 = makeGame(
          'nrl-02-003',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 9),
        );

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 2, 28),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 3),
          games: [startedSplit],
        );
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          games: [home1, home2],
        );
        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 15),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 21),
          games: [pastCutoffSplit],
        );

        final split = svc.computeSplitRoundGames(
          rounds: [r1, r2, r3],
          nrlCutoff: DateTime.utc(2026, 3, 12),
          now: now,
        );
        expect(split, isEmpty);
      });

      test('picks earlier DAU round on an even split', () {
        final g1 = makeGame(
          'nrl-02-001',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 2),
        );
        final g2 = makeGame(
          'nrl-02-002',
          League.nrl,
          2,
          DateTime.utc(2026, 3, 9),
        );

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 3),
          games: [g1],
        );
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          games: [g2],
        );

        final split = svc.computeSplitRoundGames(rounds: [r1, r2], now: now);
        expect(split, hasLength(1));
        expect(split.single.game.dbkey, 'nrl-02-002');
        expect(split.single.assignedRoundNumber, 2);
        expect(split.single.homeRoundNumber, 1);
      });
    });

    group('admin start and cutoff validation', () {
      const svc = RoundsLinkingService();

      DAUComp makeComp(List<DAURound> rounds, {DateTime? nrlCutoff}) => DAUComp(
        dbkey: 'c1',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        nrlRegularCompEndDateUTC: nrlCutoff,
        daurounds: rounds,
      );

      Game makeGame(
        String key,
        League league,
        DateTime kickoff, {
        Scoring? scoring,
      }) => Game(
        dbkey: key,
        league: league,
        homeTeam: league == League.nrl ? nrlTeam('h') : aflTeam('h'),
        awayTeam: league == League.nrl ? nrlTeam('a') : aflTeam('a'),
        location: 'X',
        startTimeUTC: kickoff,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: scoring,
      );

      test('rejects start edit that crosses a scored game (including scored <2h after kickoff)', () {
        final rounds = [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 3),
          ),
          DAURound(
            dAUroundNumber: 2,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          ),
        ];
        final comp = makeComp(rounds);
        final scoredGame = makeGame(
          'nrl-01-001',
          League.nrl,
          DateTime.utc(2026, 3, 2, 10),
          scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
        );

        final error = svc.validateRoundStartDateEdit(
          comp: comp,
          rounds: rounds,
          editedRoundNumber: 2,
          newStartDateUTC: DateTime.utc(2026, 3, 2, 9),
          allGames: [scoredGame],
        );

        expect(error, isNotNull);
      });

      test('allows start edit across a started, unscored game', () {
        final rounds = [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 3),
          ),
          DAURound(
            dAUroundNumber: 2,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          ),
        ];
        final comp = makeComp(rounds);
        // Another scored game in R1 keeps R1 not fully scored? Even if R1 has an
        // unscored game at 10:00, moving R2 start to 09:00 must be allowed if R1
        // is not fully scored and no scored game moves.
        final startedUnscored = makeGame(
          'nrl-01-002',
          League.nrl,
          DateTime.utc(2026, 3, 2, 10),
        );
        final scoredEarlier = makeGame(
          'nrl-01-001',
          League.nrl,
          DateTime.utc(2026, 3, 1, 10),
          scoring: Scoring(homeTeamScore: 10, awayTeamScore: 4),
        );

        final error = svc.validateRoundStartDateEdit(
          comp: comp,
          rounds: rounds,
          editedRoundNumber: 2,
          newStartDateUTC: DateTime.utc(2026, 3, 2, 9),
          allGames: [scoredEarlier, startedUnscored],
        );

        expect(error, isNull);
      });

      test('rejects start edit that is not strictly increasing or precedes fully scored previous round end', () {
        final rounds = [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 1),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 3, 12),
          ),
          DAURound(
            dAUroundNumber: 2,
            firstGameKickOffUTC: DateTime.utc(2026, 3, 8),
            lastGameKickOffUTC: DateTime.utc(2026, 3, 10),
          ),
        ];
        final comp = makeComp(rounds);
        final scoredGame = makeGame(
          'nrl-01-001',
          League.nrl,
          DateTime.utc(2026, 3, 2),
          scoring: Scoring(homeTeamScore: 10, awayTeamScore: 8),
        );

        // Equal to Round 1 start -> rejected
        expect(
          svc.validateRoundStartDateEdit(
            comp: comp,
            rounds: rounds,
            editedRoundNumber: 2,
            newStartDateUTC: DateTime.utc(2026, 3, 1),
            allGames: const [],
          ),
          isNotNull,
        );

        // After Round 1 game, but before fully scored Round 1's stored end (Mar 3 12:00) -> rejected
        expect(
          svc.validateRoundStartDateEdit(
            comp: comp,
            rounds: rounds,
            editedRoundNumber: 2,
            newStartDateUTC: DateTime.utc(2026, 3, 3, 11),
            allGames: [scoredGame],
          ),
          isNotNull,
        );
      });

      test(
        'rejects league cutoff edit earlier than a scored game in that league',
        () {
          final scoredNrl = makeGame(
            'nrl-20-001',
            League.nrl,
            DateTime.utc(2026, 8, 25, 10),
            scoring: Scoring(homeTeamScore: 22, awayTeamScore: 18),
          );
          final unscoredAfl = makeGame(
            'afl-20-001',
            League.afl,
            DateTime.utc(2026, 8, 26, 10),
          );

          expect(
            svc.validateLeagueCutoffEdit(
              league: League.nrl,
              newCutoffUTC: DateTime.utc(2026, 8, 24),
              allGames: [scoredNrl, unscoredAfl],
            ),
            isNotNull,
          );
          expect(
            svc.validateLeagueCutoffEdit(
              league: League.afl,
              newCutoffUTC: DateTime.utc(2026, 8, 24),
              allGames: [scoredNrl, unscoredAfl],
            ),
            isNull,
          );
        },
      );
    });
  });
}
