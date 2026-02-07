import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('DAUComp model helpers', () {
    Team t(String key, League l) => Team(dbkey: key, name: key, league: l);

    test('latestsCompletedRoundNumber uses +6h past threshold', () {
      final now = DateTime.now().toUtc();
      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 3)),
        lastGameKickOffUTC: now.subtract(const Duration(days: 2)),
      );
      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now.subtract(const Duration(days: 1)),
        lastGameKickOffUTC: now.subtract(const Duration(hours: 7)), // +6h => past
      );
      final r3 = DAURound(
        dAUroundNumber: 3,
        firstGameKickOffUTC: now.subtract(const Duration(hours: 2)),
        lastGameKickOffUTC: now.subtract(const Duration(hours: 1)), // +6h => future
      );
      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2, r3],
      );

      expect(comp.latestsCompletedRoundNumber(), 2);
    });

    test('latestRoundWithGamesCompletedOrUnderway prioritizes started over ended', () {
      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.allGamesEnded;
      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.started;
      final r3 = DAURound(
        dAUroundNumber: 3,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.notStarted;

      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2, r3],
      );

      expect(comp.latestRoundWithGamesCompletedOrUnderway(), 2);
    });

    test('firstNotEndedRoundNumber finds first not-started/started from end', () {
      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.allGamesEnded;
      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.started;
      final r3 = DAURound(
        dAUroundNumber: 3,
        firstGameKickOffUTC: DateTime.now().toUtc(),
        lastGameKickOffUTC: DateTime.now().toUtc(),
      )..roundState = RoundState.notStarted;
      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2, r3],
      );

      expect(comp.firstNotEndedRoundNumber(), 2);
    });

    test('pixelHeightUpToRound sums headers and game heights', () {
      final now = DateTime.now().toUtc();
      final nrlTeam = t('nrl-a', League.nrl);
      final nrlTeam2 = t('nrl-b', League.nrl);
      final aflTeam = t('afl-a', League.afl);
      final gNRL = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrlTeam,
        awayTeam: nrlTeam2,
        location: 'X',
        startTimeUTC: now,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      final gAFL = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: aflTeam,
        awayTeam: aflTeam,
        location: 'Y',
        startTimeUTC: now,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now,
        lastGameKickOffUTC: now,
        games: [gNRL, gAFL],
      )..roundState = RoundState.notStarted;
      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now,
        lastGameKickOffUTC: now,
        games: [gNRL], // AFL no games => noGamesCardHeight
      )..roundState = RoundState.notStarted;

      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2],
      );

      final header = DAURound.leagueHeaderHeight;
      final noGames = DAURound.noGamesCardHeight;
      final gameCard = Game.gameCardHeight;

      // Round 1: two headers + 2 games
      final r1Height = header + header + (2 * gameCard);
      // Round 2: NRL header + AFL no-games + 1 game
      final r2Height = header + noGames + (1 * gameCard);
      // plus welcome header of 200 for roundNumber > 0
      final expected = 200 + r1Height + r2Height;

      expect(comp.pixelHeightUpToRound(2), expected);
    });
  });
}

