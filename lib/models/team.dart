import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Team implements Comparable<Team> {
  String dbkey;
  final String name;
  final League league;
  String? logoURI;

  //constructor
  Team(
      {required this.dbkey,
      required this.name,
      required this.league,
      this.logoURI});

  factory Team.fromJson(Map<String, dynamic> data, String key) {
    return Team(
      dbkey: key,
      name: data['name'],
      league: League.values.byName(data['league']),
      logoURI: data['logoURI'] == null ? null : data['logoURI'] as String,
    );
  }
  Map<String, String?> toJson() {
    return {
      'name': name,
      'logoURI': logoURI,
      'league': league.name,
    };
  }

  SvgPicture getHomeTeamLogo(Game game) {
    return SvgPicture.asset(
        game.homeTeam.logoURI != null
            ? game.homeTeam.logoURI!
            : league == League.nrl
                ? 'assets/teams/nrl.svg'
                : 'assets/teams/afl.svg', //assign the league logo if the team logo is not available
        height: 20,
        width: 20);
  }

  SvgPicture getAwayTeamLogo(Game game) {
    return SvgPicture.asset(
        game.awayTeam.logoURI != null
            ? game.awayTeam.logoURI!
            : league == League.nrl
                ? 'assets/teams/nrl.svg'
                : 'assets/teams/afl.svg', //assign the league logo if the team logo is not available
        height: 20,
        width: 20);
  }

  @override
  // method used to provide default sort for Teams in a List[]
  int compareTo(Team other) {
    return name.compareTo(other.name);
  }
}
