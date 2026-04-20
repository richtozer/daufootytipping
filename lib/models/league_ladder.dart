import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';

enum LeagueLadderHighlightBand { none, finals, wildcard }

class LeagueLadder {
  League league;
  List<LadderTeam> teams;

  LeagueLadder({required this.league, required this.teams});

  // static method to generate ordinal number in string format
  static String ordinal(int number) {
    if (number < 1) return '';
    if (number % 100 >= 11 && number % 100 <= 13) {
      return '${number}th';
    }
    switch (number % 10) {
      case 1:
        return '${number}st';
      case 2:
        return '${number}nd';
      case 3:
        return '${number}rd';
      default:
        return '${number}th';
    }
  }

  void sortLadder() {
    teams.sort((a, b) {
      // Primary sort: points (descending)
      if (b.points.compareTo(a.points) != 0) {
        return b.points.compareTo(a.points);
      }

      if (league == League.nrl) {
        // Match the official NRL ladder: tie on points is split by points differential.
        final differentialCompare = _pointsDifferential(
          b,
        ).compareTo(_pointsDifferential(a));
        if (differentialCompare != 0) {
          return differentialCompare;
        }

        if (b.percentage.compareTo(a.percentage) != 0) {
          return b.percentage.compareTo(a.percentage);
        }
      } else {
        // AFL ladder uses percentage as the primary tie-break.
        if (b.percentage.compareTo(a.percentage) != 0) {
          return b.percentage.compareTo(a.percentage);
        }
      }

      // Next tie-break: higher scoring output.
      if (b.pointsFor.compareTo(a.pointsFor) != 0) {
        return b.pointsFor.compareTo(a.pointsFor);
      }

      // Finally, sort by team name (ascending) as a tie-breaker
      return a.teamName.compareTo(b.teamName);
    });

    // Populate originalRank after sorting
    for (int i = 0; i < teams.length; i++) {
      teams[i].originalRank = i + 1;
    }
  }

  bool usesAflWildcardFormat({int? seasonYear}) =>
      league == League.afl && seasonYear != null && seasonYear >= 2026;

  LeagueLadderHighlightBand highlightBandForRank(
    int rank, {
    int? seasonYear,
  }) {
    if (rank < 1) {
      return LeagueLadderHighlightBand.none;
    }

    if (usesAflWildcardFormat(seasonYear: seasonYear)) {
      if (rank <= 6) {
        return LeagueLadderHighlightBand.finals;
      }
      if (rank <= 10) {
        return LeagueLadderHighlightBand.wildcard;
      }
      return LeagueLadderHighlightBand.none;
    }

    return rank <= 8
        ? LeagueLadderHighlightBand.finals
        : LeagueLadderHighlightBand.none;
  }

  String? cutoffLabelForRank(
    int rank, {
    int? seasonYear,
  }) {
    if (!usesAflWildcardFormat(seasonYear: seasonYear)) {
      return null;
    }
    if (rank == 6) {
      return 'Top 6';
    }
    if (rank == 10) {
      return 'WC';
    }
    return null;
  }

  int _pointsDifferential(LadderTeam team) => team.pointsFor - team.pointsAgainst;
}
