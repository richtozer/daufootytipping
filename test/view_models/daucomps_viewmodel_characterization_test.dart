import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

void main() {
  group('DAUCompsViewModel (characterization)', () {
    test('groupGamesIntoLeagues splits and sorts games', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      final nrlHome = Team(dbkey: 'nrl-home', name: 'NRL Home', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-away', name: 'NRL Away', league: League.nrl);
      final aflHome = Team(dbkey: 'afl-home', name: 'AFL Home', league: League.afl);
      final aflAway = Team(dbkey: 'afl-away', name: 'AFL Away', league: League.afl);

      final games = <Game>[
        Game(
          dbkey: 'nrl-01-002',
          league: League.nrl,
          homeTeam: nrlHome,
          awayTeam: nrlAway,
          location: 'Suncorp',
          startTimeUTC: DateTime.parse('2025-01-01T12:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        ),
        Game(
          dbkey: 'nrl-01-001',
          league: League.nrl,
          homeTeam: nrlHome,
          awayTeam: nrlAway,
          location: 'Suncorp',
          startTimeUTC: DateTime.parse('2025-01-01T10:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        ),
        Game(
          dbkey: 'afl-01-002',
          league: League.afl,
          homeTeam: aflHome,
          awayTeam: aflAway,
          location: 'MCG',
          startTimeUTC: DateTime.parse('2025-01-02T08:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 2,
        ),
        Game(
          dbkey: 'afl-01-001',
          league: League.afl,
          homeTeam: aflHome,
          awayTeam: aflAway,
          location: 'MCG',
          startTimeUTC: DateTime.parse('2025-01-02T06:00:00Z'),
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        ),
      ];

      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-03T00:00:00Z'),
        games: games,
      );

      final grouped = vm.groupGamesIntoLeagues(round);

      expect(grouped[League.nrl]!.length, 2);
      expect(grouped[League.afl]!.length, 2);

      // Verify intra-league sorting by start time then match number
      expect(grouped[League.nrl]![0].fixtureMatchNumber, 1);
      expect(grouped[League.nrl]![1].fixtureMatchNumber, 2);
      expect(grouped[League.afl]![0].fixtureMatchNumber, 1);
      expect(grouped[League.afl]![1].fixtureMatchNumber, 2);
    });

    test('updateRoundAttribute writes correct update path', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      vm.updateRoundAttribute('comp123', 2, 'roundStartDate', '2025-01-01T00:00:00Z');

      // roundNumber is 1-based; storage uses 0-based index
      final key = '/AllDAUComps/comp123/combinedRounds2/1/roundStartDate';
      expect(vm.updates.containsKey(key), isTrue);
      expect(vm.updates[key], '2025-01-01T00:00:00Z');
    });

    test('updateCompAttribute writes correct update path', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      vm.updateCompAttribute('comp123', 'name', 'My Comp');
      final key = '/AllDAUComps/comp123/name';
      expect(vm.updates.containsKey(key), isTrue);
      expect(vm.updates[key], 'My Comp');
    });
  });
}

