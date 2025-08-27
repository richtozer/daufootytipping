import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}
class MockTeamsViewModel extends Mock implements TeamsViewModel {}

void main() {
  group('DAUCompsViewModel ladder caching', () {
    late DAUCompsViewModel vm;
    late MockGamesViewModel mockGamesVM;
    late MockTeamsViewModel mockTeamsVM;

    // Simple team helpers
    Team t(String key) => Team(dbkey: key, name: key.toUpperCase(), league: League.nrl);

    // Create a finished game in a given round
    Game g(String key, Team h, Team a, int round, DateTime start, int home, int away) => Game(
          dbkey: key,
          league: League.nrl,
          homeTeam: h,
          awayTeam: a,
          location: 'X',
          startTimeUTC: start.toUtc(),
          fixtureRoundNumber: round,
          fixtureMatchNumber: 1,
          scoring: Scoring(homeTeamScore: home, awayTeamScore: away),
        );

    setUp(() {
      vm = DAUCompsViewModel(null, false, skipInit: true);
      mockGamesVM = MockGamesViewModel();
      mockTeamsVM = MockTeamsViewModel();

      // Select a comp so the method can run
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: <DAURound>[],
      );
      vm.setSelectedCompForTest(comp);

      // Wire the mocked GamesVM into the VM
      vm.gamesViewModel = mockGamesVM;
      when(() => mockGamesVM.teamsViewModel).thenReturn(mockTeamsVM);
    });

    test('caches calculated ladder and reuses it', () async {
      final now = DateTime.now().toUtc();
      // Teams
      final a = t('nrl-a');
      final b = t('nrl-b');
      final c = t('nrl-c');
      final d = t('nrl-d');
      final teams = [a, b, c, d];

      // 3 completed rounds, all games >3h in the past
      final games = <Game>[
        // Round 1
        g('nrl-01-001', a, b, 1, now.subtract(const Duration(hours: 24)), 12, 8),
        g('nrl-01-002', c, d, 1, now.subtract(const Duration(hours: 23)), 10, 20),
        // Round 2
        g('nrl-02-001', a, c, 2, now.subtract(const Duration(hours: 22)), 18, 6),
        g('nrl-02-002', b, d, 2, now.subtract(const Duration(hours: 21)), 7, 9),
        // Round 3
        g('nrl-03-001', a, d, 3, now.subtract(const Duration(hours: 20)), 14, 14), // draw
        g('nrl-03-002', b, c, 3, now.subtract(const Duration(hours: 19)), 3, 2),
      ];

      when(() => mockGamesVM.getGames()).thenAnswer((_) async => games);
      when(() => mockTeamsVM.groupedTeams).thenReturn({'nrl': teams});

      final l1 = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(l1, isNotNull);

      // Second call should hit cache; getGames still called once
      final l2 = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(l2, same(l1));
      verify(() => mockGamesVM.getGames()).called(1);
    });

    test('clearLeagueLadderCache invalidates cache', () async {
      final now = DateTime.now().toUtc();
      final a = t('nrl-a');
      final b = t('nrl-b');
      final cT = t('nrl-c');
      final dT = t('nrl-d');
      final teams = [a, b, cT, dT];

      final games = <Game>[
        g('nrl-01-001', a, b, 1, now.subtract(const Duration(hours: 24)), 1, 0),
        g('nrl-01-002', cT, dT, 1, now.subtract(const Duration(hours: 23)), 2, 3),
        g('nrl-02-001', a, cT, 2, now.subtract(const Duration(hours: 22)), 4, 1),
        g('nrl-02-002', b, dT, 2, now.subtract(const Duration(hours: 21)), 1, 2),
        g('nrl-03-001', a, dT, 3, now.subtract(const Duration(hours: 20)), 2, 2),
        g('nrl-03-002', b, cT, 3, now.subtract(const Duration(hours: 19)), 2, 1),
      ];

      when(() => mockGamesVM.getGames()).thenAnswer((_) async => games);
      when(() => mockTeamsVM.groupedTeams).thenReturn({'nrl': teams});

      final l1 = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(l1, isNotNull);

      vm.clearLeagueLadderCache(league: League.nrl);

      final l2 = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(l2, isNotNull);
      // After clearing cache, getGames should have been called twice total
      verify(() => mockGamesVM.getGames()).called(2);
    });

    test('forceRecalculate bypasses cache', () async {
      final now = DateTime.now().toUtc();
      final a = t('nrl-a');
      final b = t('nrl-b');
      final cT = t('nrl-c');
      final dT = t('nrl-d');
      final teams = [a, b, cT, dT];

      final games = <Game>[
        g('nrl-01-001', a, b, 1, now.subtract(const Duration(hours: 24)), 1, 0),
        g('nrl-01-002', cT, dT, 1, now.subtract(const Duration(hours: 23)), 2, 3),
        g('nrl-02-001', a, cT, 2, now.subtract(const Duration(hours: 22)), 4, 1),
        g('nrl-02-002', b, dT, 2, now.subtract(const Duration(hours: 21)), 1, 2),
        g('nrl-03-001', a, dT, 3, now.subtract(const Duration(hours: 20)), 2, 2),
        g('nrl-03-002', b, cT, 3, now.subtract(const Duration(hours: 19)), 2, 1),
      ];

      when(() => mockGamesVM.getGames()).thenAnswer((_) async => games);
      when(() => mockTeamsVM.groupedTeams).thenReturn({'nrl': teams});

      final l1 = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(l1, isNotNull);

      final l2 = await vm.getOrCalculateLeagueLadder(League.nrl, forceRecalculate: true);
      expect(l2, isNotNull);
      // First call + forced recompute => 2 total calls
      verify(() => mockGamesVM.getGames()).called(2);
    });

    test('returns null if fewer than 3 completed rounds', () async {
      final now = DateTime.now().toUtc();
      final a = t('nrl-a');
      final b = t('nrl-b');
      final teams = [a, b];

      // Only 2 rounds completed
      final games = <Game>[
        g('nrl-01-001', a, b, 1, now.subtract(const Duration(hours: 24)), 10, 8),
        g('nrl-02-001', b, a, 2, now.subtract(const Duration(hours: 23)), 12, 4),
      ];

      when(() => mockGamesVM.getGames()).thenAnswer((_) async => games);
      when(() => mockTeamsVM.groupedTeams).thenReturn({'nrl': teams});

      final ladder = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(ladder, isNull);
    });

    test('returns null when selectedDAUComp is null', () async {
      // New instance without selected comp
      final vm2 = DAUCompsViewModel(null, false, skipInit: true);
      vm2.gamesViewModel = mockGamesVM; // even if set, method should early-return

      final ladder = await vm2.getOrCalculateLeagueLadder(League.nrl);
      expect(ladder, isNull);
      verifyNever(() => mockGamesVM.getGames());
    });

    test('returns null when gamesViewModel is null', () async {
      // selected comp is set but gamesViewModel is not
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: <DAURound>[],
      );
      vm.setSelectedCompForTest(comp);
      vm.gamesViewModel = null;

      final ladder = await vm.getOrCalculateLeagueLadder(League.nrl);
      expect(ladder, isNull);
    });
  });
}

