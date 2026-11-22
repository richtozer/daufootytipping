import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockDatabaseReference extends Mock implements DatabaseReference {}

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockTeamsViewModel extends Mock implements TeamsViewModel {}

void main() {
  DAUComp comp(String key) => DAUComp(
    dbkey: key,
    name: key,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: [],
  );
  Team team(String key) => Team(dbkey: key, name: key, league: League.afl);
  Game game(int round, String home, String away) => Game(
    dbkey: 'afl-$round-$home',
    league: League.afl,
    homeTeam: team(home),
    awayTeam: team(away),
    location: 'Ground',
    startTimeUTC: DateTime.utc(2027, 3, round),
    fixtureRoundNumber: round,
    fixtureMatchNumber: 1,
  );

  setUp(() async => di.reset());
  tearDown(() async => di.reset());

  test(
    'counts each comp on its own: a club new to the latest comp counts, '
    'and a placeholder that plays one round in each of two comps does not',
    () async {
      final comps = _MockDAUCompsViewModel();
      final teams = _MockTeamsViewModel();
      final c2026 = comp('comp-2026');
      final c2027 = comp('comp-2027');
      when(() => comps.daucomps).thenReturn([c2026, c2027]);
      when(() => teams.initialLoadComplete).thenAnswer((_) async {});
      final games = GamesViewModel(
        c2026,
        comps,
        teamsViewModel: teams,
        database: _MockDatabaseReference(),
        autoInitialize: false,
      )..completeInitialLoadForTest();
      games.testGamesByCompKey = {
        'comp-2026': [
          game(1, 'afl-Crows', 'afl-Swans'),
          game(2, 'afl-Swans', 'afl-Crows'),
          game(26, 'afl-1st', 'afl-4th'),
        ],
        'comp-2027': [
          game(1, 'afl-Bears', 'afl-Crows'),
          game(2, 'afl-Crows', 'afl-Bears'),
          game(27, 'afl-1st', 'afl-4th'),
        ],
      };

      expect(await games.teamKeysInSeveralRoundsOfAnyComp(), {
        'afl-Crows',
        'afl-Swans',
        'afl-Bears',
      });
    },
  );
}
