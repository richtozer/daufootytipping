import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
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
  late Game currentGame;
  late Game staleGame;
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
      firstGameKickOffUTC: DateTime.utc(2026, 4, 1, 10),
      lastGameKickOffUTC: DateTime.utc(2026, 4, 1, 12),
    );
    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
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

    staleGame = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2026, 4, 1, 10),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: null, awayTeamScore: null),
    );
    currentGame = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2026, 4, 1, 10),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(
        crowdSourcedScores: <CrowdSourcedScore>[
          CrowdSourcedScore(
            DateTime.utc(2026, 4, 1, 10, 30),
            ScoringTeam.home,
            'tipper-1',
            14,
            false,
          ),
          CrowdSourcedScore(
            DateTime.utc(2026, 4, 1, 10, 31),
            ScoringTeam.away,
            'tipper-1',
            0,
            false,
          ),
        ],
      ),
    );
    round.games = <Game>[currentGame];

    when(() => database.child(any())).thenReturn(database);
    when(() => database.runTransaction(any())).thenAnswer((_) async {
      return transactionResult;
    });
    when(() => transactionResult.committed).thenReturn(true);

    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);

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
        dbkey: 'nrl-01-001',
        game: staleGame,
        tipper: alice,
        tip: GameResult.a,
        submittedTimeUTC: DateTime.utc(2026, 4, 1, 9),
      ),
    ]);
  });

  tearDown(() async {
    allTipsViewModel.dispose();
    await di.reset();
  });

  test(
    'round-wide rescoring uses the latest game scoring even when cached tips hold stale game objects',
    () async {
      final viewModel = StatsViewModel(
        comp,
        gamesViewModel,
        database: database,
        autoInitialize: false,
      );
      viewModel.allTipsViewModel = allTipsViewModel;

      await viewModel.handleRoundPointsEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: <Object?>[
              <String, Map<String, int>>{
                'tipper-1': RoundStats(
                  roundNumber: 1,
                  aflPoints: 0,
                  aflMaxPoints: 0,
                  aflMarginTips: 0,
                  aflMarginUPS: 0,
                  nrlPoints: 0,
                  nrlMaxPoints: 0,
                  nrlMarginTips: 0,
                  nrlMarginUPS: 0,
                  rank: 0,
                  rankChange: 0,
                  nrlTipsOutstanding: 0,
                  aflTipsOutstanding: 0,
                ).toJson(),
              },
            ],
          ),
        ),
      );

      final result = await viewModel.updateStats(comp, round, null);

      expect(result, 'Completed updates for 1 tippers and 1 rounds.');
      final updatedRoundStats = viewModel.getScoringRoundStats(round, alice);
      expect(updatedRoundStats.nrlMarginTips, 1);
      expect(updatedRoundStats.nrlPoints, 4);
      expect(updatedRoundStats.nrlMaxPoints, 4);
      expect(updatedRoundStats.nrlMarginUPS, 1);

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
