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
  group('DAUCompsViewModel linkGamesWithRounds per-league cutoffs', () {
    late DAUCompsViewModel vm;
    late MockGamesViewModel mockGamesVM;
    late Team nrlHome, nrlAway, aflHome, aflAway;

    setUp(() {
      vm = DAUCompsViewModel(null, false, skipInit: true);
      mockGamesVM = MockGamesViewModel();
      vm.gamesViewModel = mockGamesVM;
      vm.completeOtherViewModelsForTest();
      nrlHome = Team(dbkey: 'nrl-h', name: 'NRL H', league: League.nrl);
      nrlAway = Team(dbkey: 'nrl-a', name: 'NRL A', league: League.nrl);
      aflHome = Team(dbkey: 'afl-h', name: 'AFL H', league: League.afl);
      aflAway = Team(dbkey: 'afl-a', name: 'AFL A', league: League.afl);
    });

    Game gNRL(String key, String date) => Game(
          dbkey: key,
          league: League.nrl,
          homeTeam: nrlHome,
          awayTeam: nrlAway,
          location: 'X',
          startTimeUTC: DateTime.parse(date),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );

    Game gAFL(String key, String date) => Game(
          dbkey: key,
          league: League.afl,
          homeTeam: aflHome,
          awayTeam: aflAway,
          location: 'Y',
          startTimeUTC: DateTime.parse(date),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );

    test('filters unassigned games beyond respective league cutoffs', () async {
      final cutoffNRL = '2025-01-05T00:00:00Z';
      final cutoffAFL = '2025-01-10T00:00:00Z';

      final all = <Game>[
        gNRL('nrl-keep', '2025-01-03T10:00:00Z'), // keep
        gNRL('nrl-cut', '2025-01-06T10:00:00Z'), // after NRL cutoff
        gAFL('afl-keep', '2025-01-08T10:00:00Z'), // keep
        gAFL('afl-cut', '2025-01-11T10:00:00Z'), // after AFL cutoff
      ];

      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-15T00:00:00Z'),
      );

      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round],
        nrlRegularCompEndDateUTC: DateTime.parse(cutoffNRL),
        aflRegularCompEndDateUTC: DateTime.parse(cutoffAFL),
      );
      vm.setSelectedCompForTest(comp);

      // getGames provides full set; getGamesForRound returns only within-cutoff items (as GamesVM would do)
      when(() => mockGamesVM.getGames()).thenAnswer((_) async => all);
      when(() => mockGamesVM.getGamesForRound(round)).thenAnswer((_) async => [
            all.firstWhere((g) => g.dbkey == 'nrl-keep'),
            all.firstWhere((g) => g.dbkey == 'afl-keep'),
          ]);

      await vm.linkGamesWithRounds([round]);

      // Round counts reflect kept games only
      expect(round.nrlGameCount, 1);
      expect(round.aflGameCount, 1);

      // Unassigned excludes assigned games and also excludes games beyond cutoffs
      expect(vm.unassignedGames, isEmpty);
    });
  });
}
