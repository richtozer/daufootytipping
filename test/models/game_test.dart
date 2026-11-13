import 'package:test/test.dart';

import 'package:dau_shared/services/fixture_import_applier.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/daucomp.dart';

void main() {
  group('Game model', () {
    Team nrl(String key) => Team(dbkey: key, name: key.toUpperCase(), league: League.nrl);
    Team afl(String key) => Team(dbkey: key, name: key.toUpperCase(), league: League.afl);

    test('gameState transitions across time and scoring', () {
      final now = DateTime.now().toUtc();

      final gNotStarted = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now.add(const Duration(days: 2)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      expect(gNotStarted.gameState, GameState.notStarted);

      final gStartingSoon = Game(
        dbkey: 'nrl-01-002',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now.add(const Duration(hours: 2)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
      );
      expect(gStartingSoon.gameState, GameState.startingSoon);

      final gStartedNoResult = Game(
        dbkey: 'nrl-01-003',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now.subtract(const Duration(hours: 1)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 3,
      );
      expect(gStartedNoResult.gameState, GameState.startedResultNotKnown);

      final gEnded = Game(
        dbkey: 'nrl-01-004',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now.subtract(const Duration(hours: 3)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 4,
        scoring: Scoring(homeTeamScore: 10, awayTeamScore: 8),
      );
      expect(gEnded.gameState, GameState.startedResultKnown);
    });

    test('compareTo sorts by league then time then match number', () {
      final now = DateTime.now().toUtc();
      final gNRL1 = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      final gNRL2 = Game(
        dbkey: 'nrl-01-002',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: now,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
      );
      final gAFL = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: afl('afl-a'),
        awayTeam: afl('afl-b'),
        location: 'Y',
        startTimeUTC: now.subtract(const Duration(days: 1)),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      final list = [gAFL, gNRL2, gNRL1];
      list.sort();

      // NRL should come before AFL due to league index ordering
      expect(list.first.league, League.nrl);
      // Within same league, tiebreak by match number
      expect(list[0].fixtureMatchNumber, 1);
      expect(list[1].fixtureMatchNumber, 2);
      expect(list[2].league, League.afl);
    });

    test('toJson/fromJson preserves key fields', () {
      final now = DateTime.now().toUtc();
      final home = nrl('nrl-a');
      final away = nrl('nrl-b');
      final g = Game(
        dbkey: 'nrl-01-007',
        league: League.nrl,
        homeTeam: home,
        awayTeam: away,
        location: 'Suncorp',
        startTimeUTC: now,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 7,
        scoring: Scoring(homeTeamScore: 1, awayTeamScore: 2),
      );

      final json = g.toJson();
      final from = Game.fromJson('nrl-01-007', json, home, away);

      expect(from.league, League.nrl);
      expect(from.fixtureRoundNumber, 1);
      expect(from.fixtureMatchNumber, 7);
      expect(from.location, 'Suncorp');
      expect(from.dbkey, 'nrl-01-007');
    });

    test(
      'getDAURound respects round start boundaries and before-round-1 games',
      () {
        final now = DateTime.now().toUtc();
        final home = nrl('nrl-a');
        final away = nrl('nrl-b');
        final start = now;
        final end = now.add(const Duration(hours: 2));
        final round = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: start,
          lastGameKickOffUTC: end,
        );
        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [round],
        );

        final gBeforeStart = Game(
          dbkey: 'nrl-01-000',
          league: League.nrl,
          homeTeam: home,
          awayTeam: away,
          location: 'X',
          startTimeUTC: start.subtract(const Duration(seconds: 1)),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 0,
        );
        final gAtStart = Game(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          homeTeam: home,
          awayTeam: away,
          location: 'X',
          startTimeUTC: start,
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );
        final gAtEnd = Game(
          dbkey: 'nrl-01-002',
          league: League.nrl,
          homeTeam: home,
          awayTeam: away,
          location: 'X',
          startTimeUTC: end,
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        );

        expect(gBeforeStart.getDAURound(comp), isNull);
        expect(gAtStart.getDAURound(comp)!.dAUroundNumber, 1);
        expect(gAtEnd.getDAURound(comp)!.dAUroundNumber, 1);
      },
    );

    test('old inclusive per-round rule on raw JSON and new start-only rule agree with ends from recalculateRoundEndDates', () {
      List<int> oldInclusiveRoundsFromRawJson(
        Game game,
        List<Map<String, dynamic>> rawRounds, {
        DateTime? aflCutoffUTC,
        DateTime? nrlCutoffUTC,
      }) {
        if (game.league == League.afl &&
            aflCutoffUTC != null &&
            game.startTimeUTC.isAfter(aflCutoffUTC)) {
          return const <int>[];
        }
        if (game.league == League.nrl &&
            nrlCutoffUTC != null &&
            game.startTimeUTC.isAfter(nrlCutoffUTC)) {
          return const <int>[];
        }
        final matches = <int>[];
        for (var i = 0; i < rawRounds.length; i++) {
          final raw = rawRounds[i];
          final start = DateTime.parse(
            (raw['adminOverrideRoundStartDate'] ?? raw['roundStartDate'])
                as String,
          ).toUtc();
          final end = DateTime.parse(
            (raw['adminOverrideRoundEndDate'] ?? raw['roundEndDate'])
                as String,
          ).toUtc();
          if (!game.startTimeUTC.isBefore(start) &&
              !game.startTimeUTC.isAfter(end)) {
            matches.add(i + 1);
          }
        }
        return matches;
      }

      Game makeGame(String dbkey, DateTime kickoff, {int roundNum = 1, int matchNum = 1}) => Game(
        dbkey: dbkey,
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: kickoff,
        fixtureRoundNumber: roundNum,
        fixtureMatchNumber: matchNum,
      );

      // Build raw DB JSON with:
      // - R1 overlapping R2 via a leftover adminOverrideRoundEndDate
      // - Close rounds (< 3h gap between R1 game at 08:00 and R2 start at 10:00)
      // - R3 empty
      // - R4 final round
      final rawRounds = <Map<String, dynamic>>[
        <String, dynamic>{
          'roundStartDate': '2026-03-05T06:00:00Z',
          'roundEndDate': '2026-03-05T12:00:00Z',
          'adminOverrideRoundStartDate': '2026-03-05T05:00:00Z',
          'adminOverrideRoundEndDate': '2026-03-06T20:00:00Z', // leftover!
        },
        <String, dynamic>{
          'roundStartDate': '2026-03-06T10:00:00Z',
          'roundEndDate': '2026-03-07T12:00:00Z',
        },
        <String, dynamic>{
          'roundStartDate': '2026-03-08T10:00:00Z',
          'roundEndDate': '2026-03-08T20:00:00Z',
        },
        <String, dynamic>{
          'roundStartDate': '2026-03-10T05:00:00Z',
          'roundEndDate': '2026-03-10T12:00:00Z',
        },
      ];

      // Demonstrate that old clients apply leftover adminOverrideRoundEndDate and
      // match TWO rounds for a game kicking off after R2 start.
      final overlapGame = makeGame('nrl-02-001', DateTime.utc(2026, 3, 6, 11, 0), roundNum: 2);
      expect(oldInclusiveRoundsFromRawJson(overlapGame, rawRounds), [1, 2]);

      // Clear leftover adminOverrideRoundEndDate and recalculate roundEndDate.
      for (final raw in rawRounds) {
        raw.remove('adminOverrideRoundEndDate');
      }
      final rounds = [
        for (var i = 0; i < rawRounds.length; i++) DAURound.fromJson(rawRounds[i], i + 1),
      ];
      final comp = DAUComp(
        name: '2026',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: rounds,
      );
      const applier = FixtureImportApplier();
      final changed = applier.recalculateRoundEndDates(
        comp: comp,
        gameUpdates: const [],
        existingGames: <String, dynamic>{
          'nrl-01-001': <String, dynamic>{'DateUtc': '2026-03-06 08:00:00Z'},
          'nrl-02-001': <String, dynamic>{'DateUtc': '2026-03-06 11:00:00Z'},
          // R3 is empty.
          'nrl-04-001': <String, dynamic>{'DateUtc': '2026-03-11 08:00:00Z'},
        },
      );
      for (final entry in changed.entries) {
        rawRounds[entry.key]['roundEndDate'] = entry.value;
      }

      final timestamps = [
        DateTime.utc(2026, 3, 5, 4, 59, 59), // before R1
        DateTime.utc(2026, 3, 5, 5, 0, 0), // exact R1 override start
        DateTime.utc(2026, 3, 6, 8, 0, 0), // R1 game (<3h before R2)
        DateTime.utc(2026, 3, 6, 9, 59, 59), // exact R1 capped end
        DateTime.utc(2026, 3, 6, 10, 0, 0), // exact R2 start
        DateTime.utc(2026, 3, 6, 11, 0, 0), // R2 game
        DateTime.utc(2026, 3, 6, 14, 0, 0), // exact R2 calculated end
        DateTime.utc(2026, 3, 8, 10, 0, 0), // empty R3 start == end
        DateTime.utc(2026, 3, 10, 5, 0, 0), // exact R4 start
        DateTime.utc(2026, 3, 11, 11, 0, 0), // exact R4 extended end
      ];
      for (var i = 0; i < timestamps.length; i++) {
        final g = makeGame('nrl-ts-$i', timestamps[i], matchNum: i + 1);
        final newRound = g.getDAURound(comp)?.dAUroundNumber;
        final expectedOld = newRound == null ? const <int>[] : <int>[newRound];
        expect(
          oldInclusiveRoundsFromRawJson(g, rawRounds),
          equals(expectedOld),
          reason: 'Mismatch at timestamp ${timestamps[i]}',
        );
      }

      // P1 #2 scenario: Round 1 becomes fully scored after its last unscored
      // game moves into Round 2 because Round 2 start moved earlier.
      final p1RawRounds = <Map<String, dynamic>>[
        <String, dynamic>{
          'roundStartDate': '2026-04-01T17:00:00Z',
          'roundEndDate': '2026-04-01T23:00:00Z',
        },
        <String, dynamic>{
          'roundStartDate': '2026-04-02T10:00:00Z',
          'roundEndDate': '2026-04-02T23:00:00Z',
          'adminOverrideRoundStartDate': '2026-04-01T19:00:00Z',
        },
      ];
      final p1Rounds = [
        for (var i = 0; i < p1RawRounds.length; i++)
          DAURound.fromJson(p1RawRounds[i], i + 1),
      ];
      final p1Comp = DAUComp(
        name: '2026-p1',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: p1Rounds,
      );
      final p1Changed = applier.recalculateRoundEndDates(
        comp: p1Comp,
        gameUpdates: const [],
        existingGames: <String, dynamic>{
          'nrl-01-001': <String, dynamic>{
            'DateUtc': '2026-04-01 18:00:00Z',
            'HomeTeamScore': 20,
            'AwayTeamScore': 10,
          },
          'nrl-01-002': <String, dynamic>{'DateUtc': '2026-04-01 20:00:00Z'},
        },
      );
      for (final entry in p1Changed.entries) {
        p1RawRounds[entry.key]['roundEndDate'] = entry.value;
      }

      final movedGame = makeGame('nrl-01-002', DateTime.utc(2026, 4, 1, 20, 0), matchNum: 2);
      final scoredGame = makeGame('nrl-01-001', DateTime.utc(2026, 4, 1, 18, 0), matchNum: 1);
      expect(scoredGame.getDAURound(p1Comp)?.dAUroundNumber, 1);
      expect(oldInclusiveRoundsFromRawJson(scoredGame, p1RawRounds), [1]);
      expect(movedGame.getDAURound(p1Comp)?.dAUroundNumber, 2);
      expect(oldInclusiveRoundsFromRawJson(movedGame, p1RawRounds), [2]);
    });

    test('getDAURound assigns a game postponed into the gap after round 1 end to round 1', () {
      final r1Start = DateTime.utc(2026, 3, 5, 6, 0);
      final r1End = DateTime.utc(2026, 3, 8, 12, 0);
      final r2Start = DateTime.utc(2026, 3, 12, 6, 0);
      final r2End = DateTime.utc(2026, 3, 15, 12, 0);
      final comp = DAUComp(
        name: '2026',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: r1Start,
            lastGameKickOffUTC: r1End,
          ),
          DAURound(
            dAUroundNumber: 2,
            firstGameKickOffUTC: r2Start,
            lastGameKickOffUTC: r2End,
          ),
        ],
      );

      final postponedIntoGap = Game(
        dbkey: 'nrl-01-008',
        league: League.nrl,
        homeTeam: nrl('nrl-a'),
        awayTeam: nrl('nrl-b'),
        location: 'X',
        startTimeUTC: DateTime.utc(2026, 3, 10, 8, 0),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 8,
      );

      expect(postponedIntoGap.getDAURound(comp)?.dAUroundNumber, 1);
    });

    test(
      'getDAURound leaves final round unbounded except by per-league cutoffs',
      () {
        final r1Start = DateTime.utc(2026, 8, 27, 6, 0);
        final r1End = DateTime.utc(2026, 8, 30, 12, 0);
        final nrlCutoff = DateTime.utc(2026, 9, 1, 0, 0);
        final comp = DAUComp(
          name: '2026',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          nrlRegularCompEndDateUTC: nrlCutoff,
          daurounds: [
            DAURound(
              dAUroundNumber: 1,
              firstGameKickOffUTC: r1Start,
              lastGameKickOffUTC: r1End,
            ),
          ],
        );

        final aflAfterEndNoCutoff = Game(
          dbkey: 'afl-24-009',
          league: League.afl,
          homeTeam: afl('afl-a'),
          awayTeam: afl('afl-b'),
          location: 'MCG',
          startTimeUTC: DateTime.utc(2026, 9, 3, 9, 0),
          fixtureRoundNumber: 24,
          fixtureMatchNumber: 9,
        );
        final nrlPastCutoff = Game(
          dbkey: 'nrl-27-001',
          league: League.nrl,
          homeTeam: nrl('nrl-a'),
          awayTeam: nrl('nrl-b'),
          location: 'Suncorp',
          startTimeUTC: DateTime.utc(2026, 9, 3, 9, 0),
          fixtureRoundNumber: 27,
          fixtureMatchNumber: 1,
        );
        final nrlBeforeCutoffAfterEnd = Game(
          dbkey: 'nrl-26-008',
          league: League.nrl,
          homeTeam: nrl('nrl-a'),
          awayTeam: nrl('nrl-b'),
          location: 'Suncorp',
          startTimeUTC: DateTime.utc(2026, 8, 31, 10, 0),
          fixtureRoundNumber: 26,
          fixtureMatchNumber: 8,
        );

        expect(aflAfterEndNoCutoff.getDAURound(comp)?.dAUroundNumber, 1);
        expect(nrlBeforeCutoffAfterEnd.getDAURound(comp)?.dAUroundNumber, 1);
        expect(nrlPastCutoff.getDAURound(comp), isNull);
      },
    );
  });
}

