import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class FakeDAUComp extends Fake implements DAUComp {}

class FakeDAURound extends Fake implements DAURound {}

class FakeTipper extends Fake implements Tipper {}

class FakeGame extends Fake implements Game {}

class FakeTeam extends Fake implements Team {}

void main() {
  late MockDatabaseReference rootDb;
  late MockDatabaseReference gamesRef;
  late StreamController<DatabaseEvent> gamesController;
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockTeamsViewModel teamsViewModel;
  late DAUComp comp;
  late DAURound round;
  late Team homeTeam;
  late Team awayTeam;

  Future<void> settleAsyncWork() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, Object?> gameJson({
    required int? homeScore,
    required int? awayScore,
    String dateUtc = '2026-04-06 18:00:00Z',
  }) {
    return <String, Object?>{
      'AwayTeam': 'Away',
      'AwayTeamScore': awayScore,
      'DateUtc': dateUtc,
      'HomeTeam': 'Home',
      'HomeTeamScore': homeScore,
      'Location': 'Stadium',
      'MatchNumber': 1,
      'RoundNumber': 1,
    };
  }

  setUpAll(() {
    registerFallbackValue(FakeDAUComp());
    registerFallbackValue(FakeDAURound());
    registerFallbackValue(FakeTipper());
    registerFallbackValue(FakeGame());
    registerFallbackValue(FakeTeam());
  });

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    rootDb = MockDatabaseReference();
    gamesRef = MockDatabaseReference();
    gamesController = StreamController<DatabaseEvent>.broadcast();
    dauCompsViewModel = MockDAUCompsViewModel();
    teamsViewModel = MockTeamsViewModel();

    round = DAURound(
      dAUroundNumber: 1,
      firstGameKickOffUTC: DateTime.utc(2026, 4, 6, 17),
      lastGameKickOffUTC: DateTime.utc(2026, 4, 6, 21),
    );
    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[round],
    );
    homeTeam = Team(dbkey: 'nrl-Home', name: 'Home', league: League.nrl);
    awayTeam = Team(dbkey: 'nrl-Away', name: 'Away', league: League.nrl);

    when(() => rootDb.child('/DAUCompsGames/comp-1')).thenReturn(gamesRef);
    when(() => gamesRef.onValue).thenAnswer((_) => gamesController.stream);
    when(() => rootDb.update(any())).thenAnswer((_) async {});
    when(() => gamesRef.get()).thenAnswer(
      (_) async => _snapshot(
        exists: true,
        value: <String, Object?>{
          'nrl-01-001': gameJson(homeScore: 14, awayScore: 8),
        },
      ),
    );

    when(() => dauCompsViewModel.initialDAUCompLoadComplete).thenAnswer(
      (_) async {},
    );
    when(() => dauCompsViewModel.linkGamesWithRounds(any())).thenAnswer(
      (_) async {},
    );

    when(() => teamsViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => teamsViewModel.findTeam('nrl-Home')).thenReturn(homeTeam);
    when(() => teamsViewModel.findTeam('nrl-Away')).thenReturn(awayTeam);
    when(() => teamsViewModel.addTeam(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await gamesController.close();
    await di.reset();
  });

  test(
    'ignores out-of-season games when loading a historical competition',
    () async {
      final historicalComp = DAUComp(
        dbkey: 'comp-1',
        name: 'DAU Footy Tipping 2023',
        aflFixtureJsonURL: Uri.parse('https://example.com/feed/json/afl-2023'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/feed/json/nrl-2023'),
        daurounds: <DAURound>[round],
      );

      final viewModel = GamesViewModel(
        historicalComp,
        dauCompsViewModel,
        teamsViewModel: teamsViewModel,
        database: rootDb,
        postWriteRefreshTimeout: const Duration(milliseconds: 50),
      );

      await settleAsyncWork();
      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(
                homeScore: 10,
                awayScore: 8,
                dateUtc: '2023-03-02 09:00:00Z',
              ),
              'nrl-01-002': gameJson(
                homeScore: 14,
                awayScore: 12,
                dateUtc: '2026-03-05 02:15:00Z',
              ),
            },
          ),
        ),
      );

      await viewModel.initialLoadComplete;
      await settleAsyncWork();

      final loadedGames = await viewModel.getGames();
      expect(loadedGames, hasLength(1));
      expect(loadedGames.single.startTimeUTC.year, 2023);
      expect(loadedGames.single.dbkey, 'nrl-01-001');

      viewModel.dispose();
    },
  );

  test(
    'saveBatchOfGameAttributes waits for refreshed stream snapshot without client rescoring',
    () async {
      late GamesViewModel viewModel;

      viewModel = GamesViewModel(
        comp,
        dauCompsViewModel,
        teamsViewModel: teamsViewModel,
        database: rootDb,
        postWriteRefreshTimeout: const Duration(milliseconds: 50),
      );

      await settleAsyncWork();
      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 10, awayScore: 8),
            },
          ),
        ),
      );
      await viewModel.initialLoadComplete;
      await settleAsyncWork();

      await viewModel.updateGameAttribute(
        'nrl-01-001',
        'HomeTeamScore',
        14,
        'nrl',
      );

      final saveFuture = viewModel.saveBatchOfGameAttributes();
      await settleAsyncWork();

      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 14, awayScore: 8),
            },
          ),
        ),
      );

      await saveFuture;

      final updatedGame = await viewModel.findGame('nrl-01-001');
      expect(updatedGame?.scoring?.homeTeamScore, 14);
      expect(updatedGame?.scoring?.awayTeamScore, 8);

      viewModel.dispose();
    },
  );

  test('refreshFromServer applies fixture scores missed by the stream', () async {
    final viewModel = GamesViewModel(
      comp,
      dauCompsViewModel,
      teamsViewModel: teamsViewModel,
      database: rootDb,
      postWriteRefreshTimeout: const Duration(milliseconds: 50),
    );

    await settleAsyncWork();
    gamesController.add(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: <String, Object?>{
            'nrl-01-001': gameJson(homeScore: null, awayScore: null),
          },
        ),
      ),
    );
    await viewModel.initialLoadComplete;
    await settleAsyncWork();
    expect(
      (await viewModel.findGame('nrl-01-001'))?.scoring?.homeTeamScore,
      isNull,
    );

    when(() => gamesRef.get()).thenAnswer(
      (_) async => _snapshot(
        exists: true,
        value: <String, Object?>{
          'nrl-01-001': gameJson(homeScore: 14, awayScore: 8),
        },
      ),
    );

    await viewModel.refreshFromServer();

    final refreshedGame = await viewModel.findGame('nrl-01-001');
    expect(refreshedGame?.scoring?.homeTeamScore, 14);
    expect(refreshedGame?.scoring?.awayTeamScore, 8);
    verify(() => gamesRef.get()).called(1);

    viewModel.dispose();
  });

  test(
    'saveBatchOfGameAttributes writes fixture score updates and leaves scoring to backend triggers',
    () async {
      Map<dynamic, dynamic>? writtenPayload;
      when(() => rootDb.update(any())).thenAnswer((invocation) async {
        writtenPayload = Map<dynamic, dynamic>.from(
          invocation.positionalArguments.single as Map,
        );
      });

      final viewModel = GamesViewModel(
        comp,
        dauCompsViewModel,
        teamsViewModel: teamsViewModel,
        database: rootDb,
        postWriteRefreshTimeout: const Duration(milliseconds: 50),
      );

      await settleAsyncWork();
      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 10, awayScore: 8),
            },
          ),
        ),
      );
      await viewModel.initialLoadComplete;
      await settleAsyncWork();

      await viewModel.updateGameAttribute(
        'nrl-01-001',
        'HomeTeamScore',
        16,
        'nrl',
      );

      expect(
        viewModel.updates,
        containsPair('/DAUCompsGames/comp-1/nrl-01-001/HomeTeamScore', 16),
      );

      final saveFuture = viewModel.saveBatchOfGameAttributes();
      await settleAsyncWork();

      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 16, awayScore: 8),
            },
          ),
        ),
      );

      await saveFuture;

      verify(() => rootDb.update(any())).called(1);
      expect(
        writtenPayload,
        containsPair('/DAUCompsGames/comp-1/nrl-01-001/HomeTeamScore', 16),
      );

      viewModel.dispose();
    },
  );

  test(
    'saveBatchOfGameAttributes falls back to direct reload when refreshed stream snapshot is missed',
    () async {
      late GamesViewModel viewModel;

      viewModel = GamesViewModel(
        comp,
        dauCompsViewModel,
        teamsViewModel: teamsViewModel,
        database: rootDb,
        postWriteRefreshTimeout: const Duration(milliseconds: 10),
      );

      await settleAsyncWork();
      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 10, awayScore: 8),
            },
          ),
        ),
      );
      await viewModel.initialLoadComplete;
      await settleAsyncWork();

      await viewModel.updateGameAttribute(
        'nrl-01-001',
        'HomeTeamScore',
        14,
        'nrl',
      );

      await viewModel.saveBatchOfGameAttributes();

      verify(() => gamesRef.get()).called(1);

      viewModel.dispose();
    },
  );

  test(
    'updateGameAttribute ignores Winner and team-name casing changes',
    () async {
      final viewModel = GamesViewModel(
        comp,
        dauCompsViewModel,
        teamsViewModel: teamsViewModel,
        database: rootDb,
        postWriteRefreshTimeout: const Duration(milliseconds: 50),
      );

      await settleAsyncWork();
      gamesController.add(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-01-001': gameJson(homeScore: 10, awayScore: 8),
            },
          ),
        ),
      );
      await viewModel.initialLoadComplete;
      await settleAsyncWork();

      await viewModel.updateGameAttribute(
        'nrl-01-001',
        'Winner',
        'Home',
        'nrl',
      );
      await viewModel.updateGameAttribute(
        'nrl-01-001',
        'AwayTeam',
        'AWAY',
        'nrl',
      );

      expect(viewModel.updates, isEmpty);

      viewModel.dispose();
    },
  );
}

MockDatabaseEvent _databaseEvent(DataSnapshot snapshot) {
  final event = MockDatabaseEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _snapshot({
  required bool exists,
  required Object? value,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
