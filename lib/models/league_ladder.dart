import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';

class LeagueLadder {
  League league;
  List<LadderTeam> teams;

  LeagueLadder({
    required this.league,
    required this.teams,
  });

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
      return b.percentage.compareTo(a.percentage);
    });
  }
}
