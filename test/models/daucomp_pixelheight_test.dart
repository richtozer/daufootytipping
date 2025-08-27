import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('DAUComp.pixelHeightUpToRound', () {
    final nrlHome = Team(dbkey: 'nrl-h', name: 'NRL H', league: League.nrl);
    final nrlAway = Team(dbkey: 'nrl-a', name: 'NRL A', league: League.nrl);
    final aflHome = Team(dbkey: 'afl-h', name: 'AFL H', league: League.afl);
    final aflAway = Team(dbkey: 'afl-a', name: 'AFL A', league: League.afl);

    Game g(League league, int match) => Game(
          dbkey: '${league.name}-01-${match.toString().padLeft(3, '0')}',
          league: league,
          homeTeam: league == League.nrl ? nrlHome : aflHome,
          awayTeam: league == League.nrl ? nrlAway : aflAway,
          location: 'X',
          startTimeUTC: DateTime.parse('2025-01-01T12:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: match,
        );

    test('calculates height including headers and games', () {
      final r1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-01T23:59:59Z'),
        games: [g(League.nrl, 1)],
      );
      r1.roundState = RoundState.notStarted;

      final r2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.parse('2025-01-08T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-08T23:59:59Z'),
        games: [g(League.nrl, 1), g(League.afl, 1)],
      );
      r2.roundState = RoundState.allGamesEnded;

      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [r1, r2],
      );

      // For round 1: welcome(200) + nrl header(103) + afl no-games(75) + games 1*128 = 506
      final expectedR1 = 200 + DAURound.leagueHeaderHeight + DAURound.noGamesCardHeight + Game.gameCardHeight;
      expect(comp.pixelHeightUpToRound(1), expectedR1);

      // For rounds 1-2 total:
      // Round 2 uses ended header (104) for both leagues, plus 2 games * 128
      final expectedR2Only = DAURound.leagueHeaderEndedHeight * 2 + (2 * Game.gameCardHeight);
      expect(comp.pixelHeightUpToRound(2), expectedR1 + expectedR2Only);
    });
  });
}

