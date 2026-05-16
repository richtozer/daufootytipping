import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_scoringtile.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

class FakeGameTipViewModel extends ChangeNotifier
    implements GameTipViewModel {
  FakeGameTipViewModel({required this.game, required Tip tip}) : _tip = tip;

  final Tip _tip;

  @override
  Game game;

  @override
  Tip? get tip => _tip;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

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
  late StatsViewModel statsViewModel;

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
      dbkey: 'nrl-11-081',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2026, 5, 10, 12),
      fixtureRoundNumber: 11,
      fixtureMatchNumber: 81,
      scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
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
    when(() => database.get()).thenAnswer(
      (_) async => _snapshot(exists: false, value: null),
    );
    when(() => gamesViewModel.findGame(game.dbkey)).thenAnswer((_) async {
      return game;
    });
    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.selectedTipper).thenReturn(tipper);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[tipper]);
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);

    statsViewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
      autoInitialize: false,
    );

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<StatsViewModel>(statsViewModel);
  });

  tearDown(() async {
    statsViewModel.dispose();
    await di.reset();
  });

  testWidgets('refreshes average points when game stats arrive', (
    tester,
  ) async {
    final tip = Tip(
      dbkey: 'tip-1',
      game: game,
      tipper: tipper,
      tip: GameResult.b,
      submittedTimeUTC: DateTime.utc(2026, 5, 10, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StatsViewModel?>.value(
          value: statsViewModel,
          child: Scaffold(
            body: ScoringTile(
              tip: tip,
              gameTipsViewModel: FakeGameTipViewModel(game: game, tip: tip),
              selectedDAUComp: comp,
            ),
          ),
        ),
      ),
    );

    expect(find.text('? / 2'), findsOneWidget);

    await statsViewModel.handleGameStatsEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: <String, Object?>{
            game.dbkey: <String, Object?>{
              'pctTipA': 0.053,
              'pctTipB': 0.737,
              'pctTipC': 0.0,
              'pctTipD': 0.211,
              'pctTipE': 0.0,
              'avgScore': 1.684,
              'avgScoreTipCount': 1,
            },
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1.7 / 2'), findsOneWidget);
    expect(find.text('? / 2'), findsNothing);
  });

  testWidgets('uses cached average points after game object replacement', (
    tester,
  ) async {
    final replacementGame = Game(
      dbkey: game.dbkey,
      league: game.league,
      homeTeam: game.homeTeam,
      awayTeam: game.awayTeam,
      location: game.location,
      startTimeUTC: game.startTimeUTC,
      fixtureRoundNumber: game.fixtureRoundNumber,
      fixtureMatchNumber: game.fixtureMatchNumber,
      scoring: game.scoring,
    );
    final tip = Tip(
      dbkey: 'tip-1',
      game: replacementGame,
      tipper: tipper,
      tip: GameResult.b,
      submittedTimeUTC: DateTime.utc(2026, 5, 10, 10),
    );

    statsViewModel.gamesStatsEntry[game] = GameStatsEntry(
      averagePoints: 0.0,
      averagePointsTipCount: 57,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StatsViewModel?>.value(
          value: statsViewModel,
          child: Scaffold(
            body: ScoringTile(
              tip: tip,
              gameTipsViewModel: FakeGameTipViewModel(
                game: replacementGame,
                tip: tip,
              ),
              selectedDAUComp: comp,
            ),
          ),
        ),
      ),
    );

    expect(find.text('0.0 / 2'), findsOneWidget);
    expect(find.text('? / 2'), findsNothing);
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
