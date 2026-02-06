import 'package:test/test.dart';

import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/league.dart';

void main() {
  group('Team model', () {
    test('toJson/fromJson roundtrip', () {
      final team = Team(
        dbkey: 'nrl-broncos',
        name: 'Broncos',
        league: League.nrl,
        logoURI: 'assets/teams/nrl/broncos.svg',
      );

      final json = team.toJson();
      final from = Team.fromJson(json, team.dbkey);

      expect(from.dbkey, team.dbkey);
      expect(from.name, team.name);
      expect(from.league, team.league);
      expect(from.logoURI, team.logoURI);
    });

    test('compareTo sorts by name ascending', () {
      final a = Team(dbkey: 'nrl-a', name: 'A', league: League.nrl);
      final c = Team(dbkey: 'nrl-c', name: 'C', league: League.nrl);
      final b = Team(dbkey: 'nrl-b', name: 'B', league: League.nrl);

      final list = [a, c, b];
      list.sort();

      expect(list.map((t) => t.name).toList(), ['A', 'B', 'C']);
    });
  });
}

