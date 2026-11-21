import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_geometry.dart';
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

    group('percentage-tipped visibility', () {
      test('includes officially scored games before the round has ended', () {
        final now = DateTime.now().toUtc();
        final scoredGame = makeGame(
          dbkey: 'afl-24-204',
          league: League.afl,
          matchNumber: 204,
          startTimeUTC: now.subtract(const Duration(hours: 1)),
        )..scoring = Scoring(homeTeamScore: 80, awayTeamScore: 103);
        final unscoredGame = makeGame(
          dbkey: 'afl-24-205',
          league: League.afl,
          matchNumber: 205,
          startTimeUTC: now.add(const Duration(hours: 1)),
        );
        final round = DAURound(
          dAUroundNumber: 24,
          firstGameKickOffUTC: scoredGame.startTimeUTC,
          lastGameKickOffUTC: unscoredGame.startTimeUTC,
          games: [scoredGame, unscoredGame],
        )..roundState = RoundState.started;
        final comp = DAUComp(
          name: 'Test Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [round],
        );

        final visibleGames = gamesForTipsLeagueSection(
          round,
          League.afl,
          officialFixtureScoresOnly: true,
        );
        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
          officialFixtureScoresOnly: true,
        );

        expect(visibleGames, [scoredGame]);
        expect(sections, hasLength(1));
        expect(sections.single.league, League.afl);
        expect(sections.single.bodyExtent, Game.gameCardHeight);
      });

      test('excludes games that only have interim scores', () {
        final now = DateTime.now().toUtc();
        final liveGame =
            makeGame(
                dbkey: 'nrl-24-204',
                league: League.nrl,
                matchNumber: 204,
                startTimeUTC: now.subtract(const Duration(hours: 1)),
              )
              ..scoring = Scoring(
                crowdSourcedScores: [
                  CrowdSourcedScore(
                    now,
                    ScoringTeam.home,
                    'tipper-1',
                    20,
                    false,
                  ),
                ],
              );
        final round = DAURound(
          dAUroundNumber: 24,
          firstGameKickOffUTC: liveGame.startTimeUTC,
          lastGameKickOffUTC: liveGame.startTimeUTC,
          games: [liveGame],
        );
        final comp = DAUComp(
          name: 'Test Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [round],
        );

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
          officialFixtureScoresOnly: true,
        );

        expect(sections, isEmpty);
      });
    });

    group('targetStartupSectionIndex', () {
      test(
        'targets round with live games when previous round ended recently',
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

          final sections = buildTipsLeagueSections(
            selectedComp: comp,
            cardExtent: Game.gameCardHeight,
            headerExtent: DAURound.leagueHeaderHeight,
          );

          final sectionIndex = targetStartupSectionIndex(comp, sections);

          // latestsCompletedRoundNumber() would return 0 here (round 1
          // ended only 3h ago, needs +6h), defaulting to round 1.
          // latestRoundWithGamesCompletedOrUnderway() returns 2 (round 2
          // is started), so we should target round 2 (roundIndex 1).
          expect(
            sections[sectionIndex].roundIndex,
            1,
            reason:
                'Should target round index 1 (round 2) which has live '
                'games, not round index 0 which '
                'latestsCompletedRoundNumber defaults to',
          );
        },
      );

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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final sectionIndex = targetStartupSectionIndex(comp, sections);

        // Should target round 2 (the round with live games)
        expect(
          sections[sectionIndex].roundIndex,
          1,
          reason:
              'Should target round index 1 (round 2) which has live '
              'games, not round index 0 (round 1) which is completed',
        );
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final sectionIndex = targetStartupSectionIndex(comp, sections);

        expect(
          sections[sectionIndex].roundIndex,
          3,
          reason:
              'Should target round index 3 (round 4), not the start '
              'of round 3 once round 3 has fully ended.',
        );
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
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
        expect(
          offset,
          0 * Game.gameCardHeight,
          reason:
              'Should scroll to the untipped game (index 0), '
              'not the live game (index 1)',
        );
      });

      test('skips an untipped game that has already started', () {
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
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
          makeGame(
            dbkey: 'nrl-01-002',
            league: League.nrl,
            matchNumber: 2,
            startTimeUTC: now.subtract(const Duration(hours: 1)),
          ),
          makeGame(
            dbkey: 'nrl-01-003',
            league: League.nrl,
            matchNumber: 3,
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );
        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (games) {
            for (var i = 0; i < games.length; i++) {
              if (games[i].dbkey == 'nrl-01-002' ||
                  games[i].dbkey == 'nrl-01-003') {
                return i;
              }
            }
            return -1;
          },
        );

        expect(offset, 2 * Game.gameCardHeight);
      });

      test('uses an untipped live game as the live fallback', () {
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
            startTimeUTC: now.add(const Duration(days: 1)),
          ),
          makeGame(
            dbkey: 'nrl-01-002',
            league: League.nrl,
            matchNumber: 2,
            startTimeUTC: now.subtract(const Duration(hours: 1)),
          ),
        ];

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );
        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (games) =>
              games.indexWhere((game) => game.dbkey == 'nrl-01-002'),
        );

        expect(offset, 1 * Game.gameCardHeight);
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // All tipped, so should scroll to the live game at index 1
        expect(
          offset,
          1 * Game.gameCardHeight,
          reason:
              'Should scroll to the live game (index 1) '
              'when all games are tipped',
        );
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );
        final nrlSection = sections[0];

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // From the NRL section's start, past its header and games, to the AFL
        // section's start, where the live AFL game is first.
        final expectedOffset = nrlSection.headerExtent + nrlSection.bodyExtent;
        expect(
          offset,
          expectedOffset,
          reason: 'Should scroll to the live AFL game',
        );
      });

      test('scrolls to live AFL game when NRL game is done and all tipped', () {
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
        expect(
          nrlDoneGame.gameState,
          GameState.startedResultKnown,
          reason: 'NRL game should be done with known result',
        );
        expect(
          aflLiveGame.gameState,
          GameState.startedResultNotKnown,
          reason: 'AFL game should be live',
        );

        final comp = DAUComp(
          name: 'c',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [r1],
        );

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );
        final nrlSection = sections[0];

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        // From the NRL section's start, past its header and games, to the AFL
        // section's start, where the live AFL game is first.
        final expectedOffset = nrlSection.headerExtent + nrlSection.bodyExtent;
        expect(
          offset,
          expectedOffset,
          reason:
              'Should scroll to the live AFL game, not stay at '
              'the completed NRL game',
        );
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

        final sections = buildTipsLeagueSections(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          headerExtent: DAURound.leagueHeaderHeight,
        );

        final offset = intraRoundScrollRefinement(
          selectedComp: comp,
          cardExtent: Game.gameCardHeight,
          sections: sections,
          targetSectionIndex: 0,
          firstUntippedGameIndex: (_) => -1, // all tipped
        );

        expect(offset, 0);
      });
    });

    test('a section start pins its header, with its first game below', () {
      final now = DateTime.now().toUtc();
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(hours: 1)),
        lastGameKickOffUTC: now.add(const Duration(days: 1)),
      )..roundState = RoundState.started;
      round.games = [
        makeGame(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          matchNumber: 1,
          startTimeUTC: now.subtract(const Duration(hours: 1)),
        ),
        makeGame(
          dbkey: 'afl-01-001',
          league: League.afl,
          matchNumber: 1,
          startTimeUTC: now.add(const Duration(hours: 1)),
        ),
      ];
      final comp = DAUComp(
        name: 'c',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round],
      );
      final sections = buildTipsLeagueSections(
        selectedComp: comp,
        cardExtent: Game.gameCardHeight,
        headerExtent: DAURound.leagueHeaderHeight,
      );
      const leadingExtent = 200.0;
      final aflStart = tipsSectionHeaderTop(
        sections: sections,
        sectionIndex: 1,
        leadingExtent: leadingExtent,
      );
      int pinnedAt(double offset) => pinnedTipsSectionIndex(
        sections: sections,
        scrollOffset: offset,
        leadingExtent: leadingExtent,
      );

      expect(
        aflStart,
        leadingExtent + sections.first.headerExtent + sections.first.bodyExtent,
      );
      expect(sections[pinnedAt(aflStart)].league, League.afl);
      expect(sections[pinnedAt(aflStart - 1)].league, League.nrl);
      expect(pinnedAt(leadingExtent - 1), -1, reason: 'the welcome header');
    });
  });

  group('The list\'s extents', () {
    // Welcome 200; NRL 60 + 400; AFL 60 + 400; footer 100.
    final sections = [
      for (final league in const [League.nrl, League.afl])
        TipsLeagueSection(
          roundIndex: 0,
          league: league,
          headerExtent: 60,
          bodyExtent: 400,
          gameKeys: [for (var i = 0; i < 4; i++) '${league.name}-$i'],
        ),
    ];

    test('scrolls as far as the list is taller than its viewport', () {
      double max(double viewport) => tipsMaxScrollExtent(
        sections: sections,
        leadingExtent: 200,
        footerExtent: 100,
        viewportExtent: viewport,
      );
      expect(max(500), 1220 - 500);
      expect(max(2000), 0);
    });

    test("ends with the last section's header pinned above the footer", () {
      expect(tipsEndFooterOffset(sections: sections, leadingExtent: 200), 1060);
    });

    test('tells a remeasure or a changed game from the same layout', () {
      expect(sameTipsLayout(sections, List.of(sections)), isTrue);
      final remeasured = [
        sections.first,
        TipsLeagueSection(
          roundIndex: 0,
          league: League.afl,
          headerExtent: 60,
          bodyExtent: 480,
          gameKeys: sections.last.gameKeys,
        ),
      ];
      expect(sameTipsLayout(sections, remeasured), isFalse);
      final swapped = [
        sections.first,
        TipsLeagueSection(
          roundIndex: 0,
          league: League.afl,
          headerExtent: 60,
          bodyExtent: 400,
          gameKeys: const ['afl-0', 'afl-1', 'afl-2', 'afl-new'],
        ),
      ];
      expect(sameTipsLayout(sections, swapped), isFalse);
    });
  });

  group('Keeping the reader in place across a relayout', () {
    // Two sections of four games: welcome, NRL header and games, AFL header
    // and games.
    List<TipsLeagueSection> sections(
      double card,
      double header, {
      List<String>? nrlGames,
    }) => [
      for (final league in const [League.nrl, League.afl])
        if ((league == League.nrl ? nrlGames : null) ??
                [for (var i = 0; i < 4; i++) '${league.name}-$i']
            case final games)
          TipsLeagueSection(
            roundIndex: 0,
            league: league,
            headerExtent: header,
            bodyExtent: games.isEmpty
                ? DAURound.noGamesCardHeight
                : games.length * card,
            gameKeys: games,
          ),
    ];
    final before = sections(100, 60);
    final after = sections(150, 80);

    // The welcome header is 200 tall.
    double? anchored(
      double offset, {
      List<TipsLeagueSection>? from,
      List<TipsLeagueSection>? to,
    }) => anchoredTipsScrollOffset(
      before: from ?? before,
      after: to ?? after,
      leadingExtent: 200,
      scrollOffset: offset,
    );

    // Before: 200, 60, 400, 60, 400. After: 200, 80, 600, 80, 600. Past the
    // welcome header the reader's games start below the pinned header, 60
    // before and 80 after.
    test('keeps a game and the fraction through it', () {
      // Half way through the third NRL card, below the pinned header.
      expect(anchored(200 + 250), 200 + 375);
      // A quarter of the way through the second AFL card.
      expect(anchored(200 + 60 + 400 + 125), 200 + 80 + 600 + 187.5);
    });

    test('keeps a place on the next round header as it pushes up', () {
      // The AFL header 30 into the NRL pinned header's 60, pushing it up.
      expect(anchored(200 + 400 + 30), 200 + 600 + 40);
    });

    test('stays the same distance into the end footer', () {
      expect(anchored(200 + 60 + 400 + 400 + 30), 200 + 80 + 600 + 600 + 30);
    });

    test('keeps the welcome header where it is', () {
      expect(anchored(0), 0);
      expect(anchored(100), 100);
    });

    test('moves smoothly past the welcome header', () {
      final below = anchored(199.9);
      final above = anchored(200.1);
      expect(below, isNotNull);
      expect(above, isNotNull);
      expect((above ?? 0) - (below ?? 0), lessThan(1));
    });

    test('keeps a game when another arrives above it', () {
      final grown = sections(
        150,
        80,
        nrlGames: ['nrl-new', for (var i = 0; i < 4; i++) 'nrl-$i'],
      );
      // The second AFL card, a quarter through, below one more NRL card.
      expect(anchored(200 + 60 + 400 + 125, to: grown), 200 + 80 + 750 + 187.5);
    });

    test('goes to the start of the section when its game has gone', () {
      final shrunk = sections(150, 80, nrlGames: ['nrl-0', 'nrl-1']);
      // Half way through the third NRL card, which is no longer there.
      expect(anchored(200 + 250, to: shrunk), 200);
    });

    test('goes to the start of a section whose games replace its no-games '
        'card', () {
      final empty = sections(100, 60, nrlGames: const []);
      // Into the no-games card, below the pinned NRL header.
      expect(anchored(200 + 10, from: empty), 200);
    });

    test('treats an overscroll above the top as the top', () {
      expect(anchored(-20), 0);
    });

    test('gives up when the section itself has gone', () {
      expect(anchored(300, to: after.sublist(1)), isNull);
    });
  });
}
