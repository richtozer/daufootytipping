import 'dart:async';
import 'dart:convert';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockDatabaseReference mockDb;
  late MockDatabaseReference mockGamesRef;
  late StreamController<DatabaseEvent> controller;
  late MockTeamsViewModel mockTeamsViewModel;
  late MockDAUCompsViewModel mockDauCompsViewModel;
  late DAUComp activeComp;
  late DAUComp historicalComp;
  late Team broncos;
  late Team storm;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockDb = MockDatabaseReference();
    mockGamesRef = MockDatabaseReference();
    controller = StreamController<DatabaseEvent>.broadcast();
    mockTeamsViewModel = MockTeamsViewModel();
    mockDauCompsViewModel = MockDAUCompsViewModel();

    activeComp = _comp('comp-2026', 'DAU Footy Tipping 2026');
    historicalComp = _comp('comp-2025', 'DAU Footy Tipping 2025');
    broncos = Team(dbkey: 'nrl-Broncos', name: 'Broncos', league: League.nrl);
    storm = Team(dbkey: 'nrl-Storm', name: 'Storm', league: League.nrl);

    when(() => mockTeamsViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => mockTeamsViewModel.findTeam('nrl-Broncos')).thenReturn(broncos);
    when(() => mockTeamsViewModel.findTeam('nrl-Storm')).thenReturn(storm);
    when(
      () => mockDauCompsViewModel.initialDAUCompLoadComplete,
    ).thenAnswer((_) async {});
    when(
      () => mockDauCompsViewModel.linkGamesWithRounds(any()),
    ).thenAnswer((_) async {});

    when(
      () => mockDb.child('${p.gamesPathRoot}/${activeComp.dbkey}'),
    ).thenReturn(mockGamesRef);
    when(
      () => mockDb.child('${p.gamesPathRoot}/${historicalComp.dbkey}'),
    ).thenReturn(mockGamesRef);
    when(() => mockGamesRef.onValue).thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  test('active comp can warm start from cached games', () async {
    when(() => mockDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_active_games_comp_v1': activeComp.dbkey!,
      'cached_active_games_payload_v1': jsonEncode(
        _gamesPayload(homeTeam: 'Broncos', awayTeam: 'Storm'),
      ),
    });

    final vm = GamesViewModel(
      activeComp,
      mockDauCompsViewModel,
      teamsViewModel: mockTeamsViewModel,
      db: mockDb,
    );

    await vm.initialLoadComplete;

    final games = await vm.getGames();
    expect(games, hasLength(1));
    expect(games.first.dbkey, 'nrl-01-001');

    vm.dispose();
  });

  test('historical comp ignores cached active-comp games', () async {
    when(() => mockDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_active_games_comp_v1': activeComp.dbkey!,
      'cached_active_games_payload_v1': jsonEncode(
        _gamesPayload(homeTeam: 'Broncos', awayTeam: 'Storm'),
      ),
    });

    final vm = GamesViewModel(
      historicalComp,
      mockDauCompsViewModel,
      teamsViewModel: mockTeamsViewModel,
      db: mockDb,
    );

    expect(
      vm.initialLoadComplete.timeout(const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );

    vm.dispose();
  });

  test('live snapshot replaces cached active-comp games and refreshes cache', () async {
    when(() => mockDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_active_games_comp_v1': activeComp.dbkey!,
      'cached_active_games_payload_v1': jsonEncode(
        _gamesPayload(homeTeam: 'Broncos', awayTeam: 'Storm'),
      ),
    });

    final vm = GamesViewModel(
      activeComp,
      mockDauCompsViewModel,
      teamsViewModel: mockTeamsViewModel,
      db: mockDb,
    );

    await vm.initialLoadComplete;

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: _gamesPayload(homeTeam: 'Storm', awayTeam: 'Broncos'),
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final games = await vm.getGames();
    expect(games, hasLength(1));
    expect(games.first.homeTeam.name, 'Storm');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cached_active_games_comp_v1'), activeComp.dbkey);
    expect(
      prefs.getString('cached_active_games_payload_v1'),
      contains('"HomeTeam":"Storm"'),
    );

    vm.dispose();
  });
}

DAUComp _comp(String dbKey, String name) {
  return DAUComp(
    dbkey: dbKey,
    name: name,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl.json'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl.json'),
    daurounds: <DAURound>[
      DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: DateTime.parse('2026-03-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2026-03-02T00:00:00Z'),
      ),
    ],
  );
}

Map<String, Object?> _gamesPayload({
  required String homeTeam,
  required String awayTeam,
}) {
  return <String, Object?>{
    'nrl-01-001': <String, Object?>{
      'League': 'nrl',
      'HomeTeam': homeTeam,
      'AwayTeam': awayTeam,
      'Location': 'Suncorp Stadium',
      'DateUtc': '2026-03-01T10:00:00Z',
      'RoundNumber': 1,
      'MatchNumber': 1,
      'HomeTeamScore': null,
      'AwayTeamScore': null,
    },
  };
}

MockDatabaseEvent _databaseEvent(DataSnapshot snapshot) {
  final event = MockDatabaseEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _rootSnapshot({
  required bool exists,
  required Object? value,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
