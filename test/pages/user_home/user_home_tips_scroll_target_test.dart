import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Startup scroll target', () {
    Team team(String key, League league) =>
        Team(dbkey: key, name: key, league: league);

    Game makeGame({
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

    group('targetStartupSectionIndex', () {
      test('targets round with live games when previous round ended recently',
          () {
        final now = DateTime.now().toUtc();

        // Round 1: games ended but last kickoff was only 3h ago,
        // so latestsCompletedRoundNumber (which requires +6h) returns 0.
        // However latestRoundWithGamesCompletedOrUnderway sees it as ended.
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 5)),
          lastGameKickOffUTC: now.subtract(const Duration(hours: 3)),
        )..roundState = RoundState.allGamesEnded;
        r1.games = [
          makeGame(
            dbkey: 'nrl-r1-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(hours: 5)),
          ),
          makeGame(
            dbkey: 'afl-r1-01',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(hours: 3)),
          ),
        ];

        // Round 2: has a live game (started 1h ago)
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;
        r2.games = [
          makeGame(
            dbkey: 'nrl-r2-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(hours: 1)),
          ),
          makeGame(
            dbkey: 'afl-r2-01',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
        ];

        // Round 3: not started
        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: now.add(const Duration(days: 7)),
          lastGameKickOffUTC: now.add(const Duration(days: 8)),
        )..roundState = RoundState.notStarted;
        r3.games = [
          makeGame(
            dbkey: 'nrl-r3-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 7)),
          ),
        ];

        final comp = DAUComp(
          name: 'Test Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1, r2, r3],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final sectionIndex = targetStartupSectionIndex(comp, sections);

        // latestsCompletedRoundNumber() would return 0 here (round 1
        // ended only 3h ago, needs +6h), defaulting to round 1.
        // latestRoundWithGamesCompletedOrUnderway() returns 2 (round 2
        // is started), so we should target round 2 (roundIndex 1).
        expect(sections[sectionIndex].roundIndex, 1,
            reason: 'Should target round index 1 (round 2) which has live '
                'games, not round index 0 which '
                'latestsCompletedRoundNumber defaults to');
      });

      test('targets round with live games, not just completed rounds', () {
        final now = DateTime.now().toUtc();

        // Round 1: fully completed (last game kicked off > 6h ago)
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(days: 7)),
          lastGameKickOffUTC: now.subtract(const Duration(days: 6)),
        )..roundState = RoundState.allGamesEnded;
        r1.games = [
          makeGame(
            dbkey: 'nrl-r1-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(days: 7)),
          ),
          makeGame(
            dbkey: 'afl-r1-01',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(days: 7)),
          ),
        ];

        // Round 2: has live games (started but not ended)
        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;
        r2.games = [
          makeGame(
            dbkey: 'nrl-r2-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(hours: 1)),
          ),
          makeGame(
            dbkey: 'afl-r2-01',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
        ];

        // Round 3: not started
        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: now.add(const Duration(days: 7)),
          lastGameKickOffUTC: now.add(const Duration(days: 8)),
        )..roundState = RoundState.notStarted;
        r3.games = [
          makeGame(
            dbkey: 'nrl-r3-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 7)),
          ),
        ];

        final comp = DAUComp(
          name: 'Test Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1, r2, r3],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final sectionIndex = targetStartupSectionIndex(comp, sections);

        // Should target round 2 (the round with live games)
        expect(sections[sectionIndex].roundIndex, 1,
            reason: 'Should target round index 1 (round 2) which has live '
                'games, not round index 0 (round 1) which is completed');
      });

      test('targets first upcoming round when latest round has ended', () {
        final now = DateTime.now().toUtc();

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(days: 21)),
          lastGameKickOffUTC: now.subtract(const Duration(days: 20)),
        )..roundState = RoundState.allGamesEnded;
        r1.games = [
          makeGame(
            dbkey: 'nrl-r1-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(days: 21)),
          ),
        ];

        final r2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: now.subtract(const Duration(days: 14)),
          lastGameKickOffUTC: now.subtract(const Duration(days: 13)),
        )..roundState = RoundState.allGamesEnded;
        r2.games = [
          makeGame(
            dbkey: 'nrl-r2-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(days: 14)),
          ),
        ];

        final r3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: now.subtract(const Duration(days: 5)),
          lastGameKickOffUTC: now.subtract(const Duration(days: 4)),
        )..roundState = RoundState.allGamesEnded;
        r3.games = [
          makeGame(
            dbkey: 'nrl-r3-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(days: 5)),
          ),
        ];

        final r4 = DAURound(
          dAUroundNumber: 4,
          firstGameKickOffUTC: now.add(const Duration(days: 2)),
          lastGameKickOffUTC: now.add(const Duration(days: 4)),
        )..roundState = RoundState.notStarted;
        r4.games = [
          makeGame(
            dbkey: 'nrl-r4-01',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 2)),
          ),
        ];

        final comp = DAUComp(
          name: 'Test Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1, r2, r3, r4],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final sectionIndex = targetStartupSectionIndex(comp, sections);

        expect(sections[sectionIndex].roundIndex, 3,
            reason: 'Should target round index 3 (round 4), not the start '
                'of round 3 once round 3 has fully ended.');
      });

      test('returns 0 for empty sections', () {
        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [],
        );

        expect(targetStartupSectionIndex(comp, []), 0);
      });
    });

    group('intraRoundScrollRefinement', () {
      test('prioritizes untipped game over live game', () {
        final now = DateTime.now().toUtc();

        // Round with: game 0 (not started, untipped), game 1 (live, tipped)
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;
        r1.games = [
          makeGame(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)), // not started
          ),
          makeGame(
            dbkey: 'nrl-01-002',
            league: League.nrl,
            matchNumber: 2,
            startTimeUTC: now.subtract(const Duration(hours: 1)), // live
          ),
          makeGame(
            dbkey: 'afl-01-001',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)), // not started
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          // Game 0 is untipped
          firstUntippedGameIndex: (games) {
            for (var i = 0; i < games.length; i++) {
              if (games[i].dbkey == 'nrl-01-001') return i;
            }
            return -1;
          },
        );

        // Should scroll to game 0 (the untipped game), not game 1 (live)
        expect(offset, 0 * Game.gameCardHeight,
            reason: 'Should scroll to the untipped game (index 0), '
                'not the live game (index 1)');
      });

      test('scrolls to live game when all games are tipped', () {
        final now = DateTime.now().toUtc();

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;
        r1.games = [
          makeGame(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)), // not started
          ),
          makeGame(
            dbkey: 'nrl-01-002',
            league: League.nrl,
            matchNumber: 2,
            startTimeUTC: now.subtract(const Duration(hours: 1)), // live
          ),
          makeGame(
            dbkey: 'afl-01-001',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)), // not started
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // All tipped, so should scroll to the live game at index 1
        expect(offset, 1 * Game.gameCardHeight,
            reason: 'Should scroll to the live game (index 1) '
                'when all games are tipped');
      });

      test('falls back to untipped game when no games are live', () {
        final now = DateTime.now().toUtc();

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.add(const Duration(days: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 2)),
        )..roundState = RoundState.notStarted;
        r1.games = [
          makeGame(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
          makeGame(
            dbkey: 'nrl-01-002',
            league: League.nrl,
            matchNumber: 2,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
          makeGame(
            dbkey: 'afl-01-001',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          // Second NRL game is untipped
          firstUntippedGameIndex: (games) {
            for (var i = 0; i < games.length; i++) {
              if (games[i].dbkey == 'nrl-01-002') return i;
            }
            return -1;
          },
        );

        // No live games, so should fall back to the untipped game at index 1
        expect(offset, 1 * Game.gameCardHeight);
      });

      test('scrolls to live AFL game when all NRL games are not live', () {
        final now = DateTime.now().toUtc();

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;
        r1.games = [
          makeGame(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)), // not started
          ),
          makeGame(
            dbkey: 'afl-01-001',
            league: League.afl,
            matchNumber: 1,
            startTimeUTC: now.subtract(const Duration(hours: 1)), // live
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);
        final nrlSection = sections[0];
        final aflSection = sections[1];

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // Should scroll past NRL body + AFL header to reach the AFL live game
        final expectedOffset =
            nrlSection.bodyExtent + aflSection.headerExtent;
        expect(offset, expectedOffset,
            reason: 'Should scroll to the live AFL game');
      });

      test(
          'scrolls to live AFL game when NRL game is done and all tipped', () {
        final now = DateTime.now().toUtc();

        // Scenario: Round 3 has one NRL game that finished 3h ago with
        // scores (startedResultKnown), and one AFL game that started 1h
        // ago without scores (startedResultNotKnown / live).
        // All games are tipped. Scroll should target the live AFL game.
        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.subtract(const Duration(hours: 3)),
          lastGameKickOffUTC: now.add(const Duration(days: 1)),
        )..roundState = RoundState.started;

        // NRL game: started 3h ago, has final scores → startedResultKnown
        final nrlDoneGame = makeGame(
          dbkey: 'nrl-03-017',
          league: League.nrl,
          matchNumber: 17,
          startTimeUTC: now.subtract(const Duration(hours: 3)),
        )..scoring = Scoring(homeTeamScore: 24, awayTeamScore: 18);

        // AFL game: started 1h ago, no scores → startedResultNotKnown
        final aflLiveGame = makeGame(
          dbkey: 'afl-02-015',
          league: League.afl,
          matchNumber: 15,
          startTimeUTC: now.subtract(const Duration(hours: 1)),
        );

        r1.games = [nrlDoneGame, aflLiveGame];

        // Verify preconditions
        expect(nrlDoneGame.gameState, GameState.startedResultKnown,
            reason: 'NRL game should be done with known result');
        expect(aflLiveGame.gameState, GameState.startedResultNotKnown,
            reason: 'AFL game should be live');

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);
        final nrlSection = sections[0];
        final aflSection = sections[1];

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // Should scroll past NRL body + AFL header to reach the AFL live game
        final expectedOffset =
            nrlSection.bodyExtent + aflSection.headerExtent;
        expect(offset, expectedOffset,
            reason: 'Should scroll to the live AFL game, not stay at '
                'the completed NRL game');
      });

      test('returns 0 when no live and no untipped games', () {
        final now = DateTime.now().toUtc();

        final r1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: now.add(const Duration(days: 1)),
          lastGameKickOffUTC: now.add(const Duration(days: 2)),
        )..roundState = RoundState.notStarted;
        r1.games = [
          makeGame(
            dbkey: 'nrl-01-001',
            league: League.nrl,
            matchNumber: 1,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(selectedComp: comp);

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        expect(offset, 0);
      });
    });
  });
}
