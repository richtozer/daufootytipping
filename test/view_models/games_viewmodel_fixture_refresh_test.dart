import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/scoring_update_queue.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
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

class MockStatsViewModel extends Mock implements StatsViewModel {}

class FakeDAUComp extends Fake implements DAUComp {}

class FakeDAURound extends Fake implements DAURound {}

class FakeTipper extends Fake implements Tipper {}

class FakeGame extends Fake implements Game {}

void main() {
  late MockDatabaseReference rootDb;
  late MockDatabaseReference gamesRef;
  late StreamController<DatabaseEvent> gamesController;
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockTeamsViewModel teamsViewModel;
  late MockStatsViewModel statsViewModel;
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
  }) {
    return <String, Object?>{
      'AwayTeam': 'Away',
      'AwayTeamScore': awayScore,
      'DateUtc': '2026-04-06 18:00:00Z',
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
  });

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;
    ScoringUpdateQueue().clearQueue();

    rootDb = MockDatabaseReference();
    gamesRef = MockDatabaseReference();
    gamesController = StreamController<DatabaseEvent>.broadcast();
    dauCompsViewModel = MockDAUCompsViewModel();
    teamsViewModel = MockTeamsViewModel();
    statsViewModel = MockStatsViewModel();

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

    when(() => statsViewModel.getGamesStatsEntry(any(), any())).thenReturn(null);

    di.registerSingleton<StatsViewModel>(statsViewModel);
  });

  tearDown(() async {
    ScoringUpdateQueue().clearQueue();
    await gamesController.close();
    await di.reset();
  });

  test(
    'saveBatchOfGameAttributes waits for refreshed stream snapshot before rescoring',
    () async {
      late GamesViewModel viewModel;
      when(() => statsViewModel.updateStats(any(), any(), any())).thenAnswer((
        _,
      ) async {
        final currentGame = await viewModel.findGame('nrl-01-001');
        expect(currentGame?.scoring?.homeTeamScore, 14);
        expect(currentGame?.scoring?.awayTeamScore, 8);
        return 'ok';
      });

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

      verifyNever(() => statsViewModel.updateStats(any(), any(), any()));

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

      verify(() => statsViewModel.updateStats(comp, round, null)).called(1);
      final updatedGame = await viewModel.findGame('nrl-01-001');
      expect(updatedGame?.scoring?.homeTeamScore, 14);
      expect(updatedGame?.scoring?.awayTeamScore, 8);

      viewModel.dispose();
    },
  );

  test(
    'saveBatchOfGameAttributes falls back to direct reload when refreshed stream snapshot is missed',
    () async {
      late GamesViewModel viewModel;
      when(() => statsViewModel.updateStats(any(), any(), any())).thenAnswer((
        _,
      ) async {
        final currentGame = await viewModel.findGame('nrl-01-001');
        expect(currentGame?.scoring?.homeTeamScore, 14);
        expect(currentGame?.scoring?.awayTeamScore, 8);
        return 'ok';
      });

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
      verify(() => statsViewModel.updateStats(comp, round, null)).called(1);

      viewModel.dispose();
    },
  );

  test(
    'saveBatchOfGameAttributes queues rescoring behind an in-flight stats update',
    () async {
      final firstUpdateCompleter = Completer<void>();
      var updateStatsCallCount = 0;

      when(() => statsViewModel.updateStats(any(), any(), any())).thenAnswer((
        _,
      ) async {
        updateStatsCallCount++;
        if (updateStatsCallCount == 1) {
          await firstUpdateCompleter.future;
          return 'first';
        }
        return 'second';
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

      final firstScoringFuture = ScoringUpdateQueue().queueScoringUpdate(
        dauComp: comp,
        round: round,
        tipper: null,
        priority: 2,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(updateStatsCallCount, 1);

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
      await settleAsyncWork();

      expect(ScoringUpdateQueue().queueStatus['queueLength'], 1);

      firstUpdateCompleter.complete();

      await firstScoringFuture;
      await saveFuture;

      expect(updateStatsCallCount, 2);

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
