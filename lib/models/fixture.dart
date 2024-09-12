import 'package:daufootytipping/models/league.dart';

class Fixture {
  Uri fixtureJsonURL;
  League league;

  //Constructor
  Fixture({required this.fixtureJsonURL, required this.league});

  //fromJSON
  factory Fixture.fromJson(Map<String, dynamic> data) {
    return Fixture(
      fixtureJsonURL: Uri.parse(data['fixtureJsonURL']),
      league: League.values.byName(data['league']),
    );
  }

  //toJSON
  Map<String, dynamic> toJson() {
    return {
      'fixtureJsonURL': fixtureJsonURL.toString(),
      'league': league.name,
    };
  }
}
