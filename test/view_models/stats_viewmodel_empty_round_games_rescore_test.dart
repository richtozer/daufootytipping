import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTransactionResult extends Mock implements TransactionResult {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

void main() {
  late MockDatabaseReference database;
  late MockTransactionResult transactionResult;
  late MockTippersViewModel tippersViewModel;
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockGamesViewModel gamesViewModel;
  late DAUComp comp;
  late DAURound round;
  late Game game;
  late Tipper alice;
  late TipsViewModel allTipsViewModel;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    database = MockDatabaseReference();
    transactionResult = MockTransactionResult();
    tippersViewModel = MockTippersViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    gamesViewModel = MockGamesViewModel();

    round = DAURound(
      dAUroundNumber: 1,
      firstGameKickOffUTC: DateTime.utc(2024, 4, 1, 10),
      lastGameKickOffUTC: DateTime.utc(2024, 4, 1, 12),
    );
    comp = DAUComp(
      dbkey: 'comp-2024',
      name: 'DAU Footy Tipping 2024',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[round],
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
    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2024, 4, 1, 10),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
    );

    when(() => database.child(any())).thenReturn(database);
    when(
      () => database.runTransaction(any()),
    ).thenAnswer((_) async => transactionResult);
    when(() => transactionResult.committed).thenReturn(true);

    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);
    when(() => gamesViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(
      () => gamesViewModel.getGamesForRound(round),
    ).thenAnswer((_) async => <Game>[game]);

    when(() => tippersViewModel.selectedTipper).thenReturn(alice);
    when(() => tippersViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.addListener(any())).thenReturn(null);
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[alice]);
    when(() => tippersViewModel.findTipper('tipper-1')).thenAnswer((_) async {
      return alice;
    });

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);
    when(() => dauCompsViewModel.selectedTipperTipsViewModel).thenReturn(null);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);

    allTipsViewModel = TipsViewModel(
      tippersViewModel,
      comp,
      gamesViewModel,
      database: database,
      listenToTips: false,
    );
    allTipsViewModel.setTipsForTest(<Tip?>[
      Tip(
        dbkey: game.dbkey,
        game: game,
        tipper: alice,
        tip: GameResult.b,
        submittedTimeUTC: DateTime.utc(2024, 4, 1, 9),
      ),
    ]);
  });

  tearDown(() async {
    allTipsViewModel.dispose();
    await di.reset();
  });

  test(
    'first full rescore hydrates empty round games before scoring historical comps',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );
      viewModel.allTipsViewModel = allTipsViewModel;

      await viewModel.handleRoundScoresEventForTest(
        _databaseEvent(_snapshot(exists: false, value: null)),
      );

      expect(round.games, isEmpty);

      final result = await viewModel.updateStats(comp, null, null);

      expect(result, 'Completed updates for 1 tippers and 1 rounds.');
      expect(round.games, hasLength(1));
      expect(round.nrlGameCount, 1);
      final updatedRoundStats = viewModel.getScoringRoundStats(round, alice);
      expect(updatedRoundStats.nrlScore, 2);
      expect(updatedRoundStats.nrlMaxScore, 2);

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
  final ref = MockDatabaseReference();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  when(() => snapshot.ref).thenReturn(ref);
  when(() => ref.path).thenReturn('/Stats/comp-2024/round_stats_v2');
  return snapshot;
}
