import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

void main() {
  late MockDatabaseReference rootDb;
  late MockDatabaseReference statsRef;
  late MockDatabaseReference compRef;
  late MockDatabaseReference liveScoresRef;
  late MockDatabaseReference staleGameRef;
  late MockDatabaseReference activeGameRef;
  late MockGamesViewModel gamesViewModel;
  late DAUComp comp;
  late Game staleGame;
  late Game activeGame;

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
    staleGameRef = MockDatabaseReference();
    activeGameRef = MockDatabaseReference();
    gamesViewModel = MockGamesViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
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

    when(() => rootDb.child('/Stats')).thenReturn(statsRef);
    when(() => statsRef.child(comp.dbkey!)).thenReturn(compRef);
    when(() => compRef.child(liveScoresRoot)).thenReturn(liveScoresRef);
    when(() => liveScoresRef.child('afl-03-022')).thenReturn(staleGameRef);
    when(() => liveScoresRef.child('nrl-04-025')).thenReturn(activeGameRef);
    when(() => staleGameRef.remove()).thenAnswer((_) async {});
    when(() => activeGameRef.remove()).thenAnswer((_) async {});

    when(() => gamesViewModel.findGame(any())).thenAnswer((invocation) async {
      final gameDbKey = invocation.positionalArguments.single as String;
      switch (gameDbKey) {
        case 'afl-03-022':
          return staleGame;
        case 'nrl-04-025':
          return activeGame;
        default:
          return null;
      }
    });
  });

  tearDown(() async {
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
