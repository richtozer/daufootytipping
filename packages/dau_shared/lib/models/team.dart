import 'league.dart';

class Team implements Comparable<Team> {
  String dbkey;
  final String name;
  final League league;

  //constructor
  Team({required this.dbkey, required this.name, required this.league});

  factory Team.fromJson(Map<String, dynamic> data, String key) {
    return Team(
      dbkey: key,
      name: data['name'],
      league: League.values.byName(data['league']),
    );
  }
  Map<String, String> toJson() {
    return {'name': name, 'league': league.name};
  }

  @override
  // method used to provide default sort for Teams in a List[]
  int compareTo(Team other) {
    return name.compareTo(other.name);
  }
}
