import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';

class LeagueLadder {
  League league;
  List<LadderTeam> teams;

  LeagueLadder({required this.league, required this.teams});

  // static method to generate oridnal number in string format
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
      // Secondary sort: percentage (descending)
      if (b.percentage.compareTo(a.percentage) != 0) {
        return b.percentage.compareTo(a.percentage);
      }
      // Tertiary sort by pointsFor (descending) - good for SANFL, WAFL, VFL
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
}
