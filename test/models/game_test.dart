import 'package:test/test.dart';

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

    test('isGameInRound and getDAURound include boundaries', () {
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

      expect(gAtStart.isGameInRound(round), isTrue);
      expect(gAtEnd.isGameInRound(round), isTrue);
      expect(gAtStart.getDAURound(comp)!.dAUroundNumber, 1);
    });
  });
}

