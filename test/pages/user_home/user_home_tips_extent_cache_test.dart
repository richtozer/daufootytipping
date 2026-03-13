import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TipsTabItemExtentCache', () {
    Team team(String key, League league) =>
        Team(dbkey: key, name: key, league: league);

    Game game({
      required String dbkey,
      required League league,
      required int matchNumber,
      required DateTime startTimeUTC,
    }) {
      return Game(
        dbkey: dbkey,
        league: league,
        homeTeam: team('$dbkey-h', league),
        awayTeam: team('$dbkey-a', league),
        location: 'Stadium',
        startTimeUTC: startTimeUTC,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: matchNumber,
      );
    }

    test('builds welcome, per-league, and footer extents from round structure', () {
      final round1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2026-03-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2026-03-02T00:00:00Z'),
      );
      round1.games = [
        game(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          matchNumber: 1,
          startTimeUTC: DateTime.parse('2026-03-01T10:00:00Z'),
        ),
        game(
          dbkey: 'afl-01-001',
          league: League.afl,
          matchNumber: 1,
          startTimeUTC: DateTime.parse('2026-03-01T12:00:00Z'),
        ),
        game(
          dbkey: 'afl-01-002',
          league: League.afl,
          matchNumber: 2,
          startTimeUTC: DateTime.parse('2026-03-01T14:00:00Z'),
        ),
      ];
      round1.roundState = RoundState.allGamesEnded;

      final round2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: DateTime.parse('2026-03-08T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2026-03-09T00:00:00Z'),
      );
      round2.games = [];
      round2.roundState = RoundState.noGames;

      final comp = DAUComp(
        dbkey: 'comp-1',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: [round1, round2],
      );

      final extents = TipsTabItemExtentCache.buildExtents(comp);

      expect(
        extents,
        [
          kTipsWelcomeHeaderHeight,
          DAURound.leagueHeaderEndedHeight,
          Game.gameCardHeight,
          DAURound.leagueHeaderEndedHeight,
          2 * Game.gameCardHeight,
          DAURound.leagueHeaderHeight,
          DAURound.noGamesCardHeight,
          DAURound.leagueHeaderHeight,
          DAURound.noGamesCardHeight,
          kTipsEndFooterHeight,
        ],
      );
    });
  });
}
