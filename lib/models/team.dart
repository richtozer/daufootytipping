import 'package:daufootytipping/models/league.dart';

class Team implements Comparable<Team> {
  String dbkey;
  final String name;
  final League league;
  Uri? logoURI;

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
      logoURI: Uri.parse(data['logoURI']),
    );
  }
  toJson() {
    return {
      'name': name,
      'logoURI': logoURI.toString(),
      'league': league.name,
    };
  }

  @override
  // method used to provide default sort for DAUComp(s) in a List[]
  int compareTo(Team other) {
    return name.compareTo(other.name);
  }
}
