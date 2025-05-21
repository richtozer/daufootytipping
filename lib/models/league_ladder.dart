import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';

class LeagueLadder {
  League league;
  List<LadderTeam> teams;

  LeagueLadder({
    required this.league,
    required this.teams,
  });

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
