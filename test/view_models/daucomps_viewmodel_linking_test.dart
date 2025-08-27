import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}

void main() {
  group('DAUCompsViewModel.linkGamesWithRounds', () {
    late DAUCompsViewModel vm;
    late MockGamesViewModel mockGamesVM;

    setUp(() {
      vm = DAUCompsViewModel(null, false, skipInit: true);
      mockGamesVM = MockGamesViewModel();
      vm.gamesViewModel = mockGamesVM;
      vm.completeOtherViewModelsForTest();
    });

    test('assigns games to rounds and updates unassigned respecting cutoffs', () async {
      final nrlHome = Team(dbkey: 'nrl-h', name: 'NRL H', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-a', name: 'NRL A', league: League.nrl);
      final aflHome = Team(dbkey: 'afl-h', name: 'AFL H', league: League.afl);
      final aflAway = Team(dbkey: 'afl-a', name: 'AFL A', league: League.afl);

      final g1 = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.parse('2025-01-01T10:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      final g2 = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: aflHome,
        awayTeam: aflAway,
        location: 'MCG',
        startTimeUTC: DateTime.parse('2025-01-01T12:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
      final g3 = Game(
        dbkey: 'nrl-02-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.parse('2025-01-02T10:00:00Z'),
        fixtureRoundNumber: 2,
        fixtureMatchNumber: 1,
      );
      final g4 = Game(
        dbkey: 'afl-02-001',
        league: League.afl,
        homeTeam: aflHome,
        awayTeam: aflAway,
        location: 'MCG',
        startTimeUTC: DateTime.parse('2025-01-09T10:00:00Z'),
        fixtureRoundNumber: 2,
        fixtureMatchNumber: 1,
      );

      final rounds = <DAURound>[
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-01-01T23:59:59Z'),
        ),
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.parse('2025-01-08T00:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-01-08T23:59:59Z'),
        ),
      ];

      final comp = DAUComp(
        dbkey: 'comp123',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
        daurounds: rounds,
        aflRegularCompEndDateUTC: DateTime.parse('2025-01-09T09:00:00Z'),
      );

      vm.setSelectedCompForTest(comp);

      // Stub games
      when(() => mockGamesVM.getGames()).thenAnswer((_) async => [g1, g2, g3, g4]);
      when(() => mockGamesVM.getGamesForRound(rounds[0])).thenAnswer((_) async => [g1, g2]);
      when(() => mockGamesVM.getGamesForRound(rounds[1])).thenAnswer((_) async => <Game>[]);

      int notifyCount = 0;
      vm.addListener(() => notifyCount++);

      await vm.linkGamesWithRounds(rounds);

      // Round 1 gets two games
      expect(rounds[0].games.length, 2);
      // Round 2 has none per our stub
      expect(rounds[1].games.length, 0);

      // Unassigned should contain g3; g4 is AFL after cutoff and removed
      expect(vm.unassignedGames.map((g) => g.dbkey), contains('nrl-02-001'));
      expect(vm.unassignedGames.map((g) => g.dbkey), isNot(contains('afl-02-001')));

      // Should notify at least twice (start and end of linking)
      expect(notifyCount >= 2, isTrue);
    });
  });
}

