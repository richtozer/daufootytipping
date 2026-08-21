import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late MockDatabaseReference database;
  late MockGamesViewModel gamesViewModel;
  late MockTippersViewModel tippersViewModel;
  late DAUComp comp;
  late Game game;
  late Tipper tipper;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    database = MockDatabaseReference();
    gamesViewModel = MockGamesViewModel();
    tippersViewModel = MockTippersViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );
    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2030, 1, 1, 12),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
    );
    tipper = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'alice@example.com',
      logon: 'alice@example.com',
      name: 'Alice',
      tipperRole: TipperRole.tipper,
      compsPaidFor: <DAUComp>[comp],
    );

    when(() => database.child(any())).thenReturn(database);
    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.selectedTipper).thenReturn(tipper);
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[tipper]);
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test(
    'getGamesStatsEntry swallows transient database disconnects',
    () async {
      final readAttempted = Completer<void>();
      final uncaughtErrors = <Object>[];
      final viewModel = StatsViewModel(
        comp,
        null,
        database: database,
        autoInitialize: false,
        gameStatsRetryDelays: const [],
      );

      when(() => database.get()).thenAnswer((_) async {
        readAttempted.complete();
        throw FirebaseException(
          plugin: 'firebase_database',
          code: 'disconnected',
          message:
              'The operation had to be aborted due to a network disconnect.',
        );
      });

      await runZonedGuarded(
        () async {
          viewModel.getGamesStatsEntry(game, false);
          await readAttempted.future;
          await Future<void>.delayed(Duration.zero);
        },
        (error, _) => uncaughtErrors.add(error),
      );

      expect(uncaughtErrors, isEmpty);
      expect(viewModel.gamesStatsEntry, isEmpty);
      verify(() => database.get()).called(1);

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry retries a transient startup disconnect',
    () async {
      final listenersNotified = Completer<void>();
      final viewModel = StatsViewModel(
        comp,
        null,
        database: database,
        autoInitialize: false,
        gameStatsRetryDelays: const [Duration.zero],
      );
      viewModel.addListener(() {
        if (!listenersNotified.isCompleted) {
          listenersNotified.complete();
        }
      });
      var readCount = 0;

      when(() => database.get()).thenAnswer((_) async {
        readCount++;
        if (readCount == 1) {
          throw FirebaseException(
            plugin: 'firebase_database',
            code: 'disconnected',
            message:
                'The operation had to be aborted due to a network disconnect.',
          );
        }
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.035,
            'pctTipB': 0.772,
            'pctTipC': 0.0,
            'pctTipD': 0.193,
            'pctTipE': 0.0,
          },
        );
      });

      viewModel.getGamesStatsEntry(game, false);
      await listenersNotified.future;

      expect(
        viewModel.gameStatsEntryFor(game)?.percentageTippedHome,
        0.772,
      );
      verify(() => database.get()).called(2);

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry retries a missing startup snapshot',
    () async {
      final listenersNotified = Completer<void>();
      final viewModel = StatsViewModel(
        comp,
        null,
        database: database,
        autoInitialize: false,
        gameStatsRetryDelays: const [Duration.zero],
      );
      viewModel.addListener(() {
        if (!listenersNotified.isCompleted) {
          listenersNotified.complete();
        }
      });
      var readCount = 0;

      when(() => database.get()).thenAnswer((_) async {
        readCount++;
        if (readCount == 1) {
          return _snapshot(exists: false, value: null);
        }
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.035,
            'pctTipB': 0.772,
            'pctTipC': 0.0,
            'pctTipD': 0.193,
            'pctTipE': 0.0,
          },
        );
      });

      viewModel.getGamesStatsEntry(game, false);
      await listenersNotified.future;

      expect(
        viewModel.gameStatsEntryFor(game)?.percentageTippedHome,
        0.772,
      );
      verify(() => database.get()).called(2);

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry accepts backend finalized stats when not forced',
    () async {
      final staleZeroRead = Completer<void>();
      final completedGame = Game(
        dbkey: game.dbkey,
        league: game.league,
        homeTeam: game.homeTeam,
        awayTeam: game.awayTeam,
        location: game.location,
        startTimeUTC: DateTime.utc(2024, 4, 1, 12),
        fixtureRoundNumber: game.fixtureRoundNumber,
        fixtureMatchNumber: game.fixtureMatchNumber,
        scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
      );
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );

      when(() => database.get()).thenAnswer((_) async {
        staleZeroRead.complete();
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.0,
            'pctTipB': 0.0,
            'pctTipC': 0.0,
            'pctTipD': 0.0,
            'pctTipE': 0.0,
            'avgScore': 0.0,
          },
        );
      });

      viewModel.getGamesStatsEntry(completedGame, false);

      await staleZeroRead.future;
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.gameStatsEntryFor(completedGame)?.averagePoints, 0.0);
      verifyNever(() => database.runTransaction(any()));

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry trusts finalized stats while tipper count is unavailable',
    () async {
      final readAttempted = Completer<void>();
      final listenersNotified = Completer<void>();
      final completedGame = Game(
        dbkey: 'afl-10-082',
        league: League.afl,
        homeTeam: Team(
          dbkey: 'afl-Brisbane Lions',
          name: 'Lions',
          league: League.afl,
        ),
        awayTeam: Team(
          dbkey: 'afl-Geelong Cats',
          name: 'Cats',
          league: League.afl,
        ),
        location: 'Gabba',
        startTimeUTC: DateTime.utc(2026, 5, 14, 9, 30),
        fixtureRoundNumber: 10,
        fixtureMatchNumber: 82,
        scoring: Scoring(homeTeamScore: 76, awayTeamScore: 117),
      );
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );
      viewModel.addListener(() {
        if (!listenersNotified.isCompleted) {
          listenersNotified.complete();
        }
      });

      when(() => tippersViewModel.tippers).thenReturn(<Tipper>[]);
      when(() => database.get()).thenAnswer((_) async {
        readAttempted.complete();
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.018,
            'pctTipB': 0.895,
            'pctTipC': 0.0,
            'pctTipD': 0.088,
            'pctTipE': 0.0,
            'avgScore': 0.0,
            'avgScoreTipCount': 57,
          },
        );
      });

      viewModel.getGamesStatsEntry(completedGame, false);

      await readAttempted.future;
      await listenersNotified.future;

      expect(
        viewModel.gameStatsEntryFor(completedGame)?.averagePoints,
        0.0,
      );
      expect(
        viewModel.gameStatsEntryFor(completedGame)?.averagePointsTipCount,
        57,
      );
      verifyNever(() => database.runTransaction(any()));

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry does not remove listener-loaded stats after a missing passive read',
    () async {
      final readStarted = Completer<void>();
      final completeRead = Completer<DataSnapshot>();
      final completedGame = Game(
        dbkey: game.dbkey,
        league: game.league,
        homeTeam: game.homeTeam,
        awayTeam: game.awayTeam,
        location: game.location,
        startTimeUTC: DateTime.utc(2024, 4, 1, 12),
        fixtureRoundNumber: game.fixtureRoundNumber,
        fixtureMatchNumber: game.fixtureMatchNumber,
        scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
      );
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );

      when(() => database.get()).thenAnswer((_) async {
        readStarted.complete();
        return completeRead.future;
      });

      viewModel.getGamesStatsEntry(completedGame, false);

      await readStarted.future;
      viewModel.gamesStatsEntry[completedGame.dbkey] = GameStatsEntry(
        averagePoints: 1.25,
        averagePointsTipCount: 1,
      );
      completeRead.complete(_snapshot(exists: false, value: null));
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.gameStatsEntryFor(completedGame)?.averagePoints,
        1.25,
      );
      verifyNever(() => database.runTransaction(any()));

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry forceUpdate re-reads backend stats and replaces cache',
    () async {
      final readAttempted = Completer<void>();
      final listenersNotified = Completer<void>();
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );
      viewModel.gamesStatsEntry[game.dbkey] = GameStatsEntry(
        averagePoints: 1.0,
        averagePointsTipCount: 1,
      );
      viewModel.addListener(() {
        if (!listenersNotified.isCompleted) {
          listenersNotified.complete();
        }
      });

      when(() => database.get()).thenAnswer((_) async {
        readAttempted.complete();
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.0,
            'pctTipB': 1.0,
            'pctTipC': 0.0,
            'pctTipD': 0.0,
            'pctTipE': 0.0,
            'avgScore': 2.0,
            'avgScoreTipCount': 2,
          },
        );
      });

      viewModel.getGamesStatsEntry(game, true);

      await readAttempted.future;
      await listenersNotified.future;

      expect(viewModel.gameStatsEntryFor(game)?.averagePoints, 2.0);
      expect(viewModel.gameStatsEntryFor(game)?.averagePointsTipCount, 2);
      verify(() => database.get()).called(1);
      verifyNever(() => database.runTransaction(any()));

      viewModel.dispose();
    },
  );

  test(
    'getGamesStatsEntry trusts finalized stats with a matching tip count',
    () async {
      final readAttempted = Completer<void>();
      final listenersNotified = Completer<void>();
      final completedGame = Game(
        dbkey: game.dbkey,
        league: game.league,
        homeTeam: game.homeTeam,
        awayTeam: game.awayTeam,
        location: game.location,
        startTimeUTC: DateTime.utc(2024, 4, 1, 12),
        fixtureRoundNumber: game.fixtureRoundNumber,
        fixtureMatchNumber: game.fixtureMatchNumber,
        scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
      );
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );
      viewModel.addListener(() {
        if (!listenersNotified.isCompleted) {
          listenersNotified.complete();
        }
      });

      when(() => database.get()).thenAnswer((_) async {
        readAttempted.complete();
        return _snapshot(
          exists: true,
          value: <String, Object?>{
            'pctTipA': 0.0,
            'pctTipB': 0.0,
            'pctTipC': 0.0,
            'pctTipD': 1.0,
            'pctTipE': 0.0,
            'avgScore': 0.0,
            'avgScoreTipCount': 1,
          },
        );
      });

      viewModel.getGamesStatsEntry(completedGame, false);

      await readAttempted.future;
      await listenersNotified.future;

      expect(
        viewModel.gameStatsEntryFor(completedGame)?.averagePoints,
        0.0,
      );
      verifyNever(() => database.runTransaction(any()));

      viewModel.dispose();
    },
  );
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
