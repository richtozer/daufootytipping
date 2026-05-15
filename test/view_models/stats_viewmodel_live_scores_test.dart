import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/scoring_update_queue.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late MockDatabaseReference rootDb;
  late MockDatabaseReference statsRef;
  late MockDatabaseReference compRef;
  late MockDatabaseReference liveScoresRef;
  late MockDatabaseReference gameStatsRef;
  late MockDatabaseReference gameStatsPaidRef;
  late MockDatabaseReference gameStatsGameRef;
  late MockDatabaseReference staleGameRef;
  late MockDatabaseReference activeGameRef;
  late MockGamesViewModel gamesViewModel;
  late MockTippersViewModel tippersViewModel;
  late DAUComp comp;
  late Game staleGame;
  late Game activeGame;
  late Game secondActiveGame;
  late Tipper alice;

  Game buildGame({
    required String dbKey,
    required League league,
    required int fixtureRoundNumber,
    required int fixtureMatchNumber,
    required int? homeScore,
    required int? awayScore,
  }) {
    return Game(
      dbkey: dbKey,
      league: league,
      homeTeam: Team(
        dbkey: '${league.name}-home-$fixtureMatchNumber',
        name: 'Home $fixtureMatchNumber',
        league: league,
      ),
      awayTeam: Team(
        dbkey: '${league.name}-away-$fixtureMatchNumber',
        name: 'Away $fixtureMatchNumber',
        league: league,
      ),
      location: 'Test Stadium',
      startTimeUTC: DateTime.utc(2026, 3, 26, 9),
      fixtureRoundNumber: fixtureRoundNumber,
      fixtureMatchNumber: fixtureMatchNumber,
      scoring: Scoring(homeTeamScore: homeScore, awayTeamScore: awayScore),
    );
  }

  Map<String, Object?> liveScoreJson({
    required int homeScore,
    required int awayScore,
  }) {
    return <String, Object?>{
      'crowdSourcedScores': <Map<String, Object?>>[
        <String, Object?>{
          'gameComplete': false,
          'interimScore': homeScore,
          'scoreTeam': 'home',
          'submittedTimeUTC': '2026-03-26T09:11:40.848427Z',
          'tipperID': 'tipper-1',
        },
        <String, Object?>{
          'gameComplete': false,
          'interimScore': awayScore,
          'scoreTeam': 'away',
          'submittedTimeUTC': '2026-03-26T09:11:40.848486Z',
          'tipperID': 'tipper-1',
        },
      ],
    };
  }

  setUp(() async {
    await di.reset();

    rootDb = MockDatabaseReference();
    statsRef = MockDatabaseReference();
    compRef = MockDatabaseReference();
    liveScoresRef = MockDatabaseReference();
    gameStatsRef = MockDatabaseReference();
    gameStatsPaidRef = MockDatabaseReference();
    gameStatsGameRef = MockDatabaseReference();
    staleGameRef = MockDatabaseReference();
    activeGameRef = MockDatabaseReference();
    gamesViewModel = MockGamesViewModel();
    tippersViewModel = MockTippersViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );
    alice = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'alice@example.com',
      logon: 'alice@example.com',
      name: 'Alice',
      tipperRole: TipperRole.tipper,
      compsPaidFor: <DAUComp>[comp],
    );

    staleGame = buildGame(
      dbKey: 'afl-03-022',
      league: League.afl,
      fixtureRoundNumber: 3,
      fixtureMatchNumber: 22,
      homeScore: 68,
      awayScore: 60,
    );
    activeGame = buildGame(
      dbKey: 'nrl-04-025',
      league: League.nrl,
      fixtureRoundNumber: 4,
      fixtureMatchNumber: 25,
      homeScore: null,
      awayScore: null,
    );
    secondActiveGame = buildGame(
      dbKey: 'nrl-04-026',
      league: League.nrl,
      fixtureRoundNumber: 4,
      fixtureMatchNumber: 26,
      homeScore: null,
      awayScore: null,
    );
    comp.daurounds = <DAURound>[
      DAURound(
        dAUroundNumber: 4,
        firstGameKickOffUTC: DateTime.utc(2026, 3, 26),
        lastGameKickOffUTC: DateTime.utc(2026, 3, 27),
        games: <Game>[activeGame, secondActiveGame],
      ),
    ];

    when(() => rootDb.child('/Stats')).thenReturn(statsRef);
    when(() => statsRef.child(comp.dbkey!)).thenReturn(compRef);
    when(() => compRef.child(liveScoresRoot)).thenReturn(liveScoresRef);
    when(() => compRef.child(gameStatsRoot)).thenReturn(gameStatsRef);
    when(() => gameStatsRef.child('paid')).thenReturn(gameStatsPaidRef);
    when(() => gameStatsPaidRef.child(any())).thenReturn(gameStatsGameRef);
    when(
      () => gameStatsGameRef.get(),
    ).thenAnswer((_) async => _snapshot(exists: false, value: null));
    when(() => liveScoresRef.child('afl-03-022')).thenReturn(staleGameRef);
    when(() => liveScoresRef.child('nrl-04-025')).thenReturn(activeGameRef);
    when(() => staleGameRef.remove()).thenAnswer((_) async {});
    when(() => activeGameRef.remove()).thenAnswer((_) async {});
    when(() => liveScoresRef.update(any())).thenAnswer((_) async {});
    when(() => tippersViewModel.selectedTipper).thenReturn(alice);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[alice]);
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});

    when(() => gamesViewModel.findGame(any())).thenAnswer((invocation) async {
      final gameDbKey = invocation.positionalArguments.single as String;
      switch (gameDbKey) {
        case 'afl-03-022':
          return staleGame;
        case 'nrl-04-025':
          return activeGame;
        case 'nrl-04-026':
          return secondActiveGame;
        default:
          return null;
      }
    });

    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    ScoringUpdateQueue().clearQueue();
    await di.reset();
  });

  test(
    'filters stale live score entries when official fixture scores already exist',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: rootDb,
        autoInitialize: false,
      );

      await viewModel.handleLiveScoresEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'afl-03-022': liveScoreJson(homeScore: 28, awayScore: 14),
              'nrl-04-025': liveScoreJson(homeScore: 6, awayScore: 4),
            },
          ),
        ),
      );

      expect(viewModel.hasLiveScoresInUse, isTrue);
      expect(
        viewModel.gamesWithLiveScores.map((game) => game.dbkey).toList(),
        <String>['nrl-04-025'],
      );
      expect(
        viewModel.gamesWithLiveScores.single.scoring?.crowdSourcedScores?.length,
        2,
      );
      verify(() => staleGameRef.remove()).called(1);
      verifyNever(() => activeGameRef.remove());

      viewModel.dispose();
    },
  );

  test('hides the warning source entirely when every live score row is stale', () async {
    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: rootDb,
      autoInitialize: false,
    );

    when(
      () => gamesViewModel.findGame('nrl-04-025'),
    ).thenAnswer((_) async => buildGame(
      dbKey: 'nrl-04-025',
      league: League.nrl,
      fixtureRoundNumber: 4,
      fixtureMatchNumber: 25,
      homeScore: 16,
      awayScore: 33,
    ));

    await viewModel.handleLiveScoresEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: <String, Object?>{
            'afl-03-022': liveScoreJson(homeScore: 28, awayScore: 14),
            'nrl-04-025': liveScoreJson(homeScore: 6, awayScore: 4),
          },
        ),
      ),
    );

    expect(viewModel.hasLiveScoresInUse, isFalse);
    expect(viewModel.gamesWithLiveScores, isEmpty);
    verify(() => staleGameRef.remove()).called(1);
    verify(() => activeGameRef.remove()).called(1);

    viewModel.dispose();
  });

  test(
    'does not calculate game stats when remote live scores arrive',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: rootDb,
        autoInitialize: false,
      );

      await viewModel.handleLiveScoresEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-04-025': liveScoreJson(homeScore: 6, awayScore: 4),
            },
          ),
        ),
      );

      expect(viewModel.gamesStatsEntry[activeGame], isNull);
      expect(viewModel.allTipsViewModel, isNull);

      viewModel.dispose();
    },
  );

  test(
    'submitLiveScores writes the live scores tree in a single database update',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: rootDb,
        autoInitialize: false,
      );
      di.registerSingleton<StatsViewModel>(viewModel);

      await viewModel.handleLiveScoresEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-04-025': liveScoreJson(homeScore: 6, awayScore: 4),
              'nrl-04-026': liveScoreJson(homeScore: 12, awayScore: 10),
            },
          ),
        ),
      );

      await viewModel.submitLiveScores(
        tip: Tip(
          dbkey: 'tip-1',
          game: activeGame,
          tipper: alice,
          tip: GameResult.a,
          submittedTimeUTC: DateTime.utc(2026, 3, 26, 8),
        ),
        homeScore: '8',
        awayScore: '4',
        originalHomeScore: '6',
        originalAwayScore: '4',
        selectedDAUComp: comp,
      );

      final payload = verify(
        () => liveScoresRef.update(captureAny()),
      ).captured.single as Map;
      expect(payload.keys, containsAll(<String>['nrl-04-025', 'nrl-04-026']));
      verifyNoMoreInteractions(liveScoresRef);

      viewModel.dispose();
    },
  );

  test(
    'loads game stats from the game stats tree',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: rootDb,
        autoInitialize: false,
      );

      await viewModel.handleGameStatsEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <String, Object?>{
              'nrl-04-025': <String, Object?>{
                'pctTipA': 0.0,
                'pctTipB': 1.0,
                'pctTipC': 0.0,
                'pctTipD': 0.0,
                'pctTipE': 0.0,
                'avgScore': 2.0,
                'avgScoreTipCount': 1,
              },
            },
          ),
        ),
      );

      expect(viewModel.gamesStatsEntry[activeGame]?.averagePoints, 2.0);
      expect(viewModel.gamesStatsEntry[activeGame]?.averagePointsTipCount, 1);

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
