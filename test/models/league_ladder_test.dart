import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeagueLadder.sortLadder', () {
    test('uses points differential as the NRL tie-breaker', () {
      final bulldogs = LadderTeam(
        dbkey: 'nrl-bulldogs',
        teamName: 'Bulldogs',
        points: 8,
        pointsFor: 121,
        pointsAgainst: 134,
        percentage: 90.3,
      );
      final cowboys = LadderTeam(
        dbkey: 'nrl-cowboys',
        teamName: 'Cowboys',
        points: 8,
        pointsFor: 165,
        pointsAgainst: 181,
        percentage: 91.16,
      );

      final ladder = LeagueLadder(
        league: League.nrl,
        teams: [cowboys, bulldogs],
      );

      ladder.sortLadder();

      expect(ladder.teams.map((team) => team.teamName).toList(), [
        'Bulldogs',
        'Cowboys',
      ]);
    });

    test('uses percentage as the AFL tie-breaker', () {
      final teamHighPercentage = LadderTeam(
        dbkey: 'afl-a',
        teamName: 'AFL Team A',
        points: 8,
        pointsFor: 80,
        pointsAgainst: 50,
        percentage: 160.0,
      );
      final teamHighForLowPercentage = LadderTeam(
        dbkey: 'afl-b',
        teamName: 'AFL Team B',
        points: 8,
        pointsFor: 120,
        pointsAgainst: 90,
        percentage: 133.33,
      );

      final ladder = LeagueLadder(
        league: League.afl,
        teams: [teamHighForLowPercentage, teamHighPercentage],
      );

      ladder.sortLadder();

      expect(ladder.teams.map((team) => team.teamName).toList(), [
        'AFL Team A',
        'AFL Team B',
      ]);
    });
  });

  group('LeagueLadder display rules', () {
    test('uses Top 6 and WC cutoffs for AFL 2026 onward', () {
      final ladder = LeagueLadder(league: League.afl, teams: const []);

      expect(
        ladder.highlightBandForRank(6, seasonYear: 2026),
        LeagueLadderHighlightBand.finals,
      );
      expect(
        ladder.highlightBandForRank(7, seasonYear: 2026),
        LeagueLadderHighlightBand.wildcard,
      );
      expect(
        ladder.highlightBandForRank(10, seasonYear: 2026),
        LeagueLadderHighlightBand.wildcard,
      );
      expect(
        ladder.highlightBandForRank(11, seasonYear: 2026),
        LeagueLadderHighlightBand.none,
      );
      expect(ladder.cutoffLabelForRank(6, seasonYear: 2026), 'Top 6');
      expect(ladder.cutoffLabelForRank(10, seasonYear: 2026), 'WC');
    });

    test('keeps top 8 highlighting for AFL seasons before 2026', () {
      final ladder = LeagueLadder(league: League.afl, teams: const []);

      expect(
        ladder.highlightBandForRank(8, seasonYear: 2025),
        LeagueLadderHighlightBand.finals,
      );
      expect(
        ladder.highlightBandForRank(9, seasonYear: 2025),
        LeagueLadderHighlightBand.none,
      );
      expect(ladder.cutoffLabelForRank(6, seasonYear: 2025), isNull);
      expect(ladder.cutoffLabelForRank(10, seasonYear: 2025), isNull);
    });
  });
}
