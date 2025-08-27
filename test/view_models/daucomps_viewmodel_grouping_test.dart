import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

void main() {
  group('DAUCompsViewModel.groupGamesIntoLeagues', () {
    test('handles single-league rounds and preserves sort', () {
      final vm = DAUCompsViewModel(null, false, skipInit: true);

      final nrlHome = Team(dbkey: 'nrl-h', name: 'NRL H', league: League.nrl);
      final nrlAway = Team(dbkey: 'nrl-a', name: 'NRL A', league: League.nrl);

      // Two NRL games with different start times and match numbers
      final g1 = Game(
        dbkey: 'nrl-01-002',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.parse('2025-01-01T12:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
      );
      final g2 = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: nrlHome,
        awayTeam: nrlAway,
        location: 'Suncorp',
        startTimeUTC: DateTime.parse('2025-01-01T10:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-02T00:00:00Z'),
        games: [g1, g2],
      );

      final grouped = vm.groupGamesIntoLeagues(round);

      expect(grouped[League.afl]!.isEmpty, isTrue, reason: 'No AFL games');
      expect(grouped[League.nrl]!.length, 2);
      // Sorted by start time then match number
      expect(grouped[League.nrl]![0].fixtureMatchNumber, 1);
      expect(grouped[League.nrl]![1].fixtureMatchNumber, 2);
    });
  });
}

