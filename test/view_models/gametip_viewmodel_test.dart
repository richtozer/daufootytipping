import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

// Manual Mocks
class MockTipsViewModel extends Mock implements TipsViewModel {
  // Add a Completer for initialLoadCompleted if TipsViewModel uses one internally
  // For simplicity, we'll assume it's a direct Future or can be stubbed directly.
  // If TipsViewModel actually uses a Completer that GameTipViewModel waits on,
  // this mock might need to expose a way to complete that future.
  // For now, direct stubbing of methods is the approach.

  // Adding a getter for initialLoadCompleted to satisfy the interface
  @override
  Future<void> get initialLoadCompleted =>
      super.noSuchMethod(Invocation.getter(#initialLoadCompleted),
          returnValue: Future.value(),
          returnValueForMissingStub: Future.value());

  @override
  List<Tip?> getTipsForTipper(Tipper? tipper) =>
      super.noSuchMethod(Invocation.method(#getTipsForTipper, [tipper]),
          returnValue: <Tip?>[], returnValueForMissingStub: <Tip?>[]);

  @override
  Future<Tip?> findTip(Game? game, Tipper? tipper) =>
      super.noSuchMethod(Invocation.method(#findTip, [game, tipper]),
          returnValue: Future.value(null),
          returnValueForMissingStub: Future.value(null));
}

class MockTipper extends Mock implements Tipper {
  @override
  String get dbkey => super.noSuchMethod(Invocation.getter(#dbkey),
      returnValue: 'mockTipperKey', returnValueForMissingStub: 'mockTipperKey');
  @override
  String get name => super.noSuchMethod(Invocation.getter(#name),
      returnValue: 'Mock Tipper', returnValueForMissingStub: 'Mock Tipper');
}

class MockDAUComp extends Mock implements DAUComp {
  @override
  String get dbkey => super.noSuchMethod(Invocation.getter(#dbkey),
      returnValue: 'mockDauCompKey',
      returnValueForMissingStub: 'mockDauCompKey');
}

class MockGame extends Mock implements Game {
  @override
  String get dbkey => super.noSuchMethod(Invocation.getter(#dbkey),
      returnValue: 'mockGameKey', returnValueForMissingStub: 'mockGameKey');
  @override
  Team get homeTeam => super.noSuchMethod(Invocation.getter(#homeTeam),
      returnValue: MockTeam(), returnValueForMissingStub: MockTeam());
  @override
  Team get awayTeam => super.noSuchMethod(Invocation.getter(#awayTeam),
      returnValue: MockTeam(), returnValueForMissingStub: MockTeam());
  @override
  League get league => super.noSuchMethod(Invocation.getter(#league),
      returnValue: League.afl, returnValueForMissingStub: League.afl);
  @override
  Scoring? get scoring => super.noSuchMethod(Invocation.getter(#scoring),
      returnValue: null, returnValueForMissingStub: null);
  @override
  GameState get gameState => super.noSuchMethod(Invocation.getter(#gameState),
      returnValue: GameState.notStarted,
      returnValueForMissingStub: GameState.notStarted);
  @override
  DateTime get startTimeUTC =>
      super.noSuchMethod(Invocation.getter(#startTimeUTC),
          returnValue: DateTime.now(),
          returnValueForMissingStub: DateTime.now());
}

class MockTeam extends Mock implements Team {
  @override
  String get dbkey => super.noSuchMethod(Invocation.getter(#dbkey),
      returnValue: 'mockTeamKey', returnValueForMissingStub: 'mockTeamKey');
  @override
  String get name => super.noSuchMethod(Invocation.getter(#name),
      returnValue: 'Mock Team', returnValueForMissingStub: 'Mock Team');
  @override
  String get logoURI => super.noSuchMethod(Invocation.getter(#logoURI),
      returnValue: 'mock_logo.png', returnValueForMissingStub: 'mock_logo.png');
}

class MockScoring extends Mock implements Scoring {
  @override
  GameResult getGameResultCalculated(League league) =>
      super.noSuchMethod(Invocation.method(#getGameResultCalculated, [league]),
          returnValue: GameResult.z, returnValueForMissingStub: GameResult.z);
}

class MockTip extends Mock implements Tip {
  @override
  String get dbkey => super.noSuchMethod(Invocation.getter(#dbkey),
      returnValue: 'mockTipKey', returnValueForMissingStub: 'mockTipKey');
  @override
  Game get game => super.noSuchMethod(Invocation.getter(#game),
      returnValue: MockGame(), returnValueForMissingStub: MockGame());
  @override
  Tipper get tipper => super.noSuchMethod(Invocation.getter(#tipper),
      returnValue: MockTipper(), returnValueForMissingStub: MockTipper());
  @override
  GameResult get tip => super.noSuchMethod(Invocation.getter(#tip),
      returnValue: GameResult.z, returnValueForMissingStub: GameResult.z);
  @override
  DateTime get submittedTimeUTC =>
      super.noSuchMethod(Invocation.getter(#submittedTimeUTC),
          returnValue: DateTime.now(),
          returnValueForMissingStub: DateTime.now());
}

void main() {
  late GameTipViewModel gameTipViewModel;
  late MockTipsViewModel mockTipsViewModel;
  late MockTipper mockCurrentTipper;
  late MockDAUComp mockCurrentDAUComp;
  late MockGame mockCurrentGame;
  late MockTeam mockTeamA;
  late MockTeam mockTeamB;
  late MockTeam mockTeamC;
  late MockTeam mockTeamD;

  // Helper to create MockTeam instances
  MockTeam _createMockTeam(String key, String name) {
    final team = MockTeam();
    when(team.dbkey).thenReturn(key);
    when(team.name).thenReturn(name);
    return team;
  }

  // Helper to create MockGame instances for past games
  MockGame _createMockPastGame(String dbkey, Team home, Team away,
      League league, GameResult? actualResult,
      {bool scoringIsNull = false}) {
    final game = MockGame();
    when(game.dbkey).thenReturn(dbkey);
    when(game.homeTeam).thenReturn(home);
    when(game.awayTeam).thenReturn(away);
    when(game.league).thenReturn(league);
    when(game.startTimeUTC).thenReturn(
        DateTime.now().subtract(const Duration(days: 7))); // Past game

    if (scoringIsNull) {
      when(game.scoring).thenReturn(null);
    } else {
      final scoring = MockScoring();
      // Ensure actualResult is not null before stubbing, or provide a default
      when(scoring.getGameResultCalculated(league))
          .thenReturn(actualResult ?? GameResult.z);
      when(game.scoring).thenReturn(scoring);
    }
    return game;
  }

  // Helper to create MockTip instances
  MockTip _createMockTip(
      String tipKey, Game game, Tipper tipper, GameResult userPick) {
    final tip = MockTip();
    when(tip.dbkey).thenReturn(tipKey);
    when(tip.game).thenReturn(game);
    when(tip.tipper).thenReturn(tipper);
    when(tip.tip).thenReturn(userPick);
    when(tip.submittedTimeUTC)
        .thenReturn(DateTime.now().subtract(const Duration(days: 7)));
    return tip;
  }

  setUp(() {
    mockTipsViewModel = MockTipsViewModel();
    mockCurrentTipper = MockTipper();
    mockCurrentDAUComp = MockDAUComp();
    mockCurrentGame = MockGame();

    mockTeamA = _createMockTeam('teamA', 'Team A');
    mockTeamB = _createMockTeam('teamB', 'Team B');
    mockTeamC = _createMockTeam('teamC', 'Team C');
    mockTeamD = _createMockTeam('teamD', 'Team D');

    when(mockCurrentTipper.dbkey).thenReturn('tipper1');
    when(mockCurrentTipper.name).thenReturn('Test Tipper');
    when(mockCurrentDAUComp.dbkey).thenReturn('comp1');

    when(mockCurrentGame.dbkey).thenReturn('currentGameKey');
    when(mockCurrentGame.homeTeam).thenReturn(mockTeamA);
    when(mockCurrentGame.awayTeam).thenReturn(mockTeamB);
    when(mockCurrentGame.league).thenReturn(League.afl);
    when(mockCurrentGame.gameState).thenReturn(GameState.notStarted);
    when(mockCurrentGame.startTimeUTC)
        .thenReturn(DateTime.now().add(const Duration(days: 1))); // Future game

    // Stub for TipsViewModel's own readiness and initial tip finding
    when(mockTipsViewModel.initialLoadCompleted)
        .thenAnswer((_) async => Future.value());
    when(mockTipsViewModel.findTip(any, any)).thenAnswer(
        (_) async => null); // Default stub for the initial tip in _findTip

    gameTipViewModel = GameTipViewModel(
      mockCurrentTipper,
      mockCurrentDAUComp,
      mockCurrentGame,
      mockTipsViewModel,
    );

    // It's important to ensure that the initial _findTip call completes before each test logic that depends on its side effects.
    // GameTipViewModel's constructor calls _findTip, which is async.
    // _findTip internally calls _fetchHistoricalTipStats AFTER its own initial load.
    // So, for tests focusing purely on _fetchHistoricalTipStats via the test hook,
    // we primarily need to control getTipsForTipper.
    // The initial call to _findTip in constructor will run, we need to ensure its stubs are set up.
  });

  group('_fetchHistoricalTipStats tests', () {
    test('1. No Historical Tips', () async {
      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => []);

      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 0);
      expect(gameTipViewModel.historicalWinsOnCombination, 0);
      expect(gameTipViewModel.historicalLossesOnCombination, 0);
      expect(gameTipViewModel.historicalDrawsOnCombination, 0);
      expect(gameTipViewModel.historicalInsightsString,
          "No past tips for this team combination.");
    });

    test('2. Historical Tips Exist - No Matching Combination', () async {
      final pastGameNonMatching = _createMockPastGame(
          'pastGame1', mockTeamC, mockTeamD, League.afl, GameResult.b);
      final tipNonMatching = _createMockTip(
          'tip1', pastGameNonMatching, mockCurrentTipper, GameResult.b);

      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => [tipNonMatching]);

      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 0);
      expect(gameTipViewModel.historicalInsightsString,
          "No past tips for this team combination.");
    });

    group('3. Historical Tips with Matching Combination', () {
      test('3.1 Wins Only (Non-Draw)', () async {
        final pastGameWin = _createMockPastGame('pastGameWin', mockTeamA,
            mockTeamB, League.afl, GameResult.b); // Team A (home) wins
        final tipWin = _createMockTip('tipWin', pastGameWin, mockCurrentTipper,
            GameResult.b); // Tipper picked Team A (home)

        when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
            .thenAnswer((_) => [tipWin, tipWin]); // Two wins

        await gameTipViewModel.testHook_fetchHistoricalTipStats();

        expect(gameTipViewModel.historicalTotalTipsOnCombination, 2);
        expect(gameTipViewModel.historicalWinsOnCombination, 2);
        expect(gameTipViewModel.historicalLossesOnCombination, 0);
        expect(gameTipViewModel.historicalDrawsOnCombination, 0);
        expect(gameTipViewModel.historicalInsightsString,
            "Previously on this matchup (2 games): 2 Wins, 0 Losses, 0 Draws.");
      });

      test('3.2 Losses Only', () async {
        final pastGameLoss1 = _createMockPastGame('pastGameLoss1', mockTeamA,
            mockTeamB, League.afl, GameResult.d); // Team B (away) wins
        final tipLoss1 = _createMockTip('tipLoss1', pastGameLoss1,
            mockCurrentTipper, GameResult.b); // Tipper picked Team A (home)

        final pastGameLoss2 = _createMockPastGame('pastGameLoss2', mockTeamA,
            mockTeamB, League.afl, GameResult.b); // Team A (home) wins
        final tipLoss2 = _createMockTip('tipLoss2', pastGameLoss2,
            mockCurrentTipper, GameResult.d); // Tipper picked Team B (away)

        when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
            .thenAnswer((_) => [tipLoss1, tipLoss2]);

        await gameTipViewModel.testHook_fetchHistoricalTipStats();

        expect(gameTipViewModel.historicalTotalTipsOnCombination, 2);
        expect(gameTipViewModel.historicalWinsOnCombination, 0);
        expect(gameTipViewModel.historicalLossesOnCombination, 2);
        expect(gameTipViewModel.historicalDrawsOnCombination, 0);
        expect(gameTipViewModel.historicalInsightsString,
            "Previously on this matchup (2 games): 0 Wins, 2 Losses, 0 Draws.");
      });

      test('3.3 Correctly Predicted Draws', () async {
        final pastGameDraw = _createMockPastGame('pastGameDraw', mockTeamA,
            mockTeamB, League.afl, GameResult.c); // Actual Draw
        final tipDraw = _createMockTip('tipDraw', pastGameDraw,
            mockCurrentTipper, GameResult.c); // Tipper picked Draw

        when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper)).thenAnswer(
            (_) => [tipDraw, tipDraw]); // Two correctly predicted draws

        await gameTipViewModel.testHook_fetchHistoricalTipStats();

        expect(gameTipViewModel.historicalTotalTipsOnCombination, 2);
        expect(gameTipViewModel.historicalWinsOnCombination,
            2); // Predicting a draw correctly is a win
        expect(gameTipViewModel.historicalLossesOnCombination, 0);
        expect(gameTipViewModel.historicalDrawsOnCombination,
            2); // Also specifically a draw stat
        expect(gameTipViewModel.historicalInsightsString,
            "Previously on this matchup (2 games): 2 Wins, 0 Losses, 2 Draws.");
      });

      test('3.4 Mixed Outcomes (Wins, Losses, Correctly Predicted Draws)',
          () async {
        final pastGameWin = _createMockPastGame('pgWin', mockTeamA, mockTeamB,
            League.afl, GameResult.b); // Home win
        final tipWin = _createMockTip('tWin', pastGameWin, mockCurrentTipper,
            GameResult.b); // Correct pick

        final pastGameLoss = _createMockPastGame('pgLoss', mockTeamA, mockTeamB,
            League.afl, GameResult.d); // Away win
        final tipLoss = _createMockTip('tLoss', pastGameLoss, mockCurrentTipper,
            GameResult.b); // Incorrect pick (picked home)

        final pastGameDrawActual = _createMockPastGame('pgDrawActual',
            mockTeamA, mockTeamB, League.afl, GameResult.c); // Actual draw
        final tipDrawCorrect = _createMockTip(
            'tDrawCorrect',
            pastGameDrawActual,
            mockCurrentTipper,
            GameResult.c); // Correctly picked draw

        final pastGameDrawActual2 = _createMockPastGame('pgDrawActual2',
            mockTeamA, mockTeamB, League.afl, GameResult.c); // Actual draw
        final tipDrawIncorrect = _createMockTip(
            'tDrawIncorrect',
            pastGameDrawActual2,
            mockCurrentTipper,
            GameResult.b); // Incorrectly picked home for a draw game

        when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper)).thenAnswer(
            (_) => [tipWin, tipLoss, tipDrawCorrect, tipDrawIncorrect]);

        await gameTipViewModel.testHook_fetchHistoricalTipStats();

        expect(gameTipViewModel.historicalTotalTipsOnCombination, 4);
        expect(gameTipViewModel.historicalWinsOnCombination, 2,
            reason: "Win + CorrectDraw"); // tipWin, tipDrawCorrect
        expect(gameTipViewModel.historicalLossesOnCombination, 2,
            reason: "Loss + IncorrectDrawPick"); // tipLoss, tipDrawIncorrect
        expect(gameTipViewModel.historicalDrawsOnCombination, 1,
            reason: "Only tipDrawCorrect"); // Only tipDrawCorrect
        expect(gameTipViewModel.historicalInsightsString,
            "Previously on this matchup (4 games): 2 Wins, 2 Losses, 1 Draws.");
      });

      test('3.5 Team Order Invariance', () async {
        // Current game: TeamA (home) vs TeamB (away)
        final pastGameAB = _createMockPastGame('pgAB', mockTeamA, mockTeamB,
            League.afl, GameResult.b); // A vs B, A wins
        final tipAB = _createMockTip('tAB', pastGameAB, mockCurrentTipper,
            GameResult.b); // Picked A - WIN

        final pastGameBA = _createMockPastGame(
            'pgBA',
            mockTeamB,
            mockTeamA,
            League.afl,
            GameResult.d); // B vs A, A wins (B is home, D means away A wins)
        final tipBA = _createMockTip('tBA', pastGameBA, mockCurrentTipper,
            GameResult.d); // Picked A - WIN

        when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
            .thenAnswer((_) => [tipAB, tipBA]);

        await gameTipViewModel.testHook_fetchHistoricalTipStats();

        expect(gameTipViewModel.historicalTotalTipsOnCombination, 2);
        expect(gameTipViewModel.historicalWinsOnCombination, 2);
        expect(gameTipViewModel.historicalLossesOnCombination, 0);
        expect(gameTipViewModel.historicalDrawsOnCombination, 0);
        expect(gameTipViewModel.historicalInsightsString,
            "Previously on this matchup (2 games): 2 Wins, 0 Losses, 0 Draws.");
      });
    });

    test('4. Historical Tip is for the Current Game (Should be Excluded)',
        () async {
      final pastGameSameAsCurrent = _createMockPastGame(mockCurrentGame.dbkey,
          mockTeamA, mockTeamB, League.afl, GameResult.b);
      final tipForCurrentGame = _createMockTip(
          'tipCurrent', pastGameSameAsCurrent, mockCurrentTipper, GameResult.b);

      final pastGameDifferent = _createMockPastGame('pgDiff', mockTeamA,
          mockTeamB, League.afl, GameResult.d); // Away wins
      final tipDifferent = _createMockTip('tDiff', pastGameDifferent,
          mockCurrentTipper, GameResult.b); // Tipper picked home - LOSS

      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => [tipForCurrentGame, tipDifferent]);

      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 1,
          reason: "Only tipDifferent should be counted");
      expect(gameTipViewModel.historicalWinsOnCombination, 0);
      expect(gameTipViewModel.historicalLossesOnCombination, 1);
      expect(gameTipViewModel.historicalDrawsOnCombination, 0);
      expect(gameTipViewModel.historicalInsightsString,
          "Previously on this matchup (1 games): 0 Wins, 1 Losses, 0 Draws.");
    });

    test('5. Games with No Scoring Data (game.scoring is null)', () async {
      final pastGameNoScoring = _createMockPastGame(
          'pgNoScoring', mockTeamA, mockTeamB, League.afl, null,
          scoringIsNull: true);
      final tipNoScoring = _createMockTip(
          'tNoScoring', pastGameNoScoring, mockCurrentTipper, GameResult.b);

      final pastGameWithScoring = _createMockPastGame('pgWithScoring',
          mockTeamA, mockTeamB, League.afl, GameResult.b); // Home win
      final tipWithScoring = _createMockTip('tWithScoring', pastGameWithScoring,
          mockCurrentTipper, GameResult.b); // Correct - WIN

      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => [tipNoScoring, tipWithScoring]);

      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 1,
          reason: "tipNoScoring should be skipped");
      expect(gameTipViewModel.historicalWinsOnCombination, 1);
      expect(gameTipViewModel.historicalLossesOnCombination, 0);
      expect(gameTipViewModel.historicalDrawsOnCombination, 0);
      expect(gameTipViewModel.historicalInsightsString,
          "Previously on this matchup (1 games): 1 Wins, 0 Losses, 0 Draws.");
    });
    test(
        'NRL: Correctly Predicted Draw (GameResult.c used for NRL draw outcome)',
        () async {
      when(mockCurrentGame.league).thenReturn(
          League.nrl); // Set current game to NRL for this test context
      final pastGameNRLDraw = _createMockPastGame(
          'pastGameNRLDraw',
          mockTeamA,
          mockTeamB,
          League.nrl,
          GameResult.c); // Actual Draw (using GameResult.c as per problem)
      final tipNRLDraw = _createMockTip('tipNRLDraw', pastGameNRLDraw,
          mockCurrentTipper, GameResult.c); // Tipper picked Draw

      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => [tipNRLDraw]);

      // Re-initialize GameTipViewModel with NRL league context for the current game if necessary,
      // or ensure the _fetchHistoricalTipStats logic correctly uses pastTip.game.league for logic.
      // The current implementation of _fetchHistoricalTipStats uses pastTip.game.league, which is good.
      // For consistency in testing, we can also set the current game's league.
      gameTipViewModel = GameTipViewModel(
        // Re-init for NRL context if current game's league matters for logic under test
        mockCurrentTipper,
        mockCurrentDAUComp,
        mockCurrentGame, // This mockCurrentGame still has its league stubbed, ensure it's NRL if needed
        mockTipsViewModel,
      );
      // Ensure the mockCurrentGame used by the SUT (gameTipViewModel) has its league set to NRL if the SUT's logic depends on game.league
      // The historical stats logic primarily depends on pastTip.game.league, so this might be okay.
      // Let's explicitly set the current game to NRL for this test to be safe.
      when(mockCurrentGame.league).thenReturn(League.nrl);

      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 1);
      expect(gameTipViewModel.historicalWinsOnCombination, 1);
      expect(gameTipViewModel.historicalLossesOnCombination, 0);
      expect(gameTipViewModel.historicalDrawsOnCombination, 1);
      expect(gameTipViewModel.historicalInsightsString,
          "Previously on this matchup (1 games): 1 Wins, 0 Losses, 1 Draws.");
    });

    test('NRL: Actual Draw, Tipper picked Win (Loss for Tipper)', () async {
      when(mockCurrentGame.league).thenReturn(League.nrl);
      final pastGameNRLDraw = _createMockPastGame('pastGameNRLDraw', mockTeamA,
          mockTeamB, League.nrl, GameResult.c); // Actual Draw
      final tipNRLWin = _createMockTip('tipNRLWin', pastGameNRLDraw,
          mockCurrentTipper, GameResult.b); // Tipper picked Home Win

      gameTipViewModel = GameTipViewModel(
        mockCurrentTipper,
        mockCurrentDAUComp,
        mockCurrentGame,
        mockTipsViewModel,
      );
      when(mockCurrentGame.league).thenReturn(League.nrl);

      when(mockTipsViewModel.getTipsForTipper(mockCurrentTipper))
          .thenAnswer((_) => [tipNRLWin]);
      await gameTipViewModel.testHook_fetchHistoricalTipStats();

      expect(gameTipViewModel.historicalTotalTipsOnCombination, 1);
      expect(gameTipViewModel.historicalWinsOnCombination, 0);
      expect(gameTipViewModel.historicalLossesOnCombination, 1);
      expect(gameTipViewModel.historicalDrawsOnCombination,
          0); // Not a correctly predicted draw
      expect(gameTipViewModel.historicalInsightsString,
          "Previously on this matchup (1 games): 0 Wins, 1 Losses, 0 Draws.");
    });
  });
}

// Helper to allow listening to GameTipViewModel changes if needed for more complex scenarios
// class TestListener {
//   int callCount = 0;
//   void call() {
//     callCount++;
//   }
// }
// And then in test:
// final listener = TestListener();
// gameTipViewModel.addListener(listener.call);
// ... action ...
// expect(listener.callCount, 1);
// gameTipViewModel.removeListener(listener.call);
// This is generally not needed if directly asserting view model properties after awaiting async methods.
