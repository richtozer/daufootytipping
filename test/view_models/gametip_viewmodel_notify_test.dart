import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/unconfirmed_tips_service.dart';
import 'package:daufootytipping/services/write_acknowledgement.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

class MockTipsViewModel extends Mock implements TipsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class FakeGame extends Fake implements Game {}

class FakeTipper extends Fake implements Tipper {}

class FakeTip extends Fake implements Tip {}

void main() {
  group('GameTipViewModel games updates', () {
    late MockTipsViewModel mockTipsViewModel;
    late MockGamesViewModel mockGamesViewModel;
    late MockDatabaseReference mockDb;
    late Tipper tipper;
    late DAUComp currentComp;
    late Team homeTeam;
    late Team awayTeam;
    late VoidCallback gamesListener;
    late VoidCallback tipsListener;

    Game buildGame({
      required DateTime startTimeUTC,
      required int? homeScore,
      required int? awayScore,
    }) {
      return Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: startTimeUTC,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: Scoring(homeTeamScore: homeScore, awayTeamScore: awayScore),
      );
    }

    Future<void> settleAsyncWork() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    setUpAll(() {
      registerFallbackValue(FakeGame());
      registerFallbackValue(FakeTipper());
      registerFallbackValue(FakeTip());
    });

    setUp(() async {
      await di.reset();
      mockTipsViewModel = MockTipsViewModel();
      mockGamesViewModel = MockGamesViewModel();
      mockDb = MockDatabaseReference();

      when(() => mockTipsViewModel.addListener(any())).thenAnswer((invocation) {
        tipsListener = invocation.positionalArguments[0] as VoidCallback;
      });
      when(() => mockTipsViewModel.removeListener(any())).thenReturn(null);
      when(() => mockGamesViewModel.removeListener(any())).thenReturn(null);
      when(() => mockGamesViewModel.addListener(any()))
          .thenAnswer((invocation) {
            gamesListener = invocation.positionalArguments[0] as VoidCallback;
          });

      when(() => mockTipsViewModel.gamesViewModel)
          .thenReturn(mockGamesViewModel);
      when(() => mockTipsViewModel.initialLoadCompleted)
          .thenAnswer((_) async {});
      when(() => mockTipsViewModel.findTip(any(), any()))
          .thenAnswer((_) async => null);
      when(() => mockTipsViewModel.getTipsForTipper(any())).thenReturn([]);
      when(() => mockTipsViewModel.waitForTipUpdate(any()))
          .thenAnswer((_) async {});
      when(() => mockDb.update(any())).thenAnswer((_) async {});

      homeTeam = Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl);
      awayTeam = Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl);
      tipper = Tipper(
        dbkey: 'tipper-1',
        compsPaidFor: const [],
        authuid: 'auth-1',
        email: 'tipper@example.com',
        name: 'Tipper',
        tipperRole: TipperRole.tipper,
      );
      currentComp = DAUComp(
        dbkey: 'comp-1',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.now().toUtc().add(
              const Duration(days: 1),
            ),
            lastGameKickOffUTC: DateTime.now().toUtc().add(
              const Duration(days: 2),
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      await di.reset();
    });

    test(
      'does not notify when the updated game scores and state are unchanged',
      () async {
        final currentGame = buildGame(
          startTimeUTC: DateTime.now().toUtc().subtract(
            const Duration(hours: 4),
          ),
          homeScore: 12,
          awayScore: 8,
        );
        when(() => mockGamesViewModel.findGame(currentGame.dbkey)).thenAnswer(
          (_) async => buildGame(
            startTimeUTC: currentGame.startTimeUTC,
            homeScore: 12,
            awayScore: 8,
          ),
        );

        final vm = GameTipViewModel(
          tipper,
          currentComp,
          currentGame,
          mockTipsViewModel,
          database: mockDb,
        );
        var notifications = 0;
        vm.addListener(() {
          notifications++;
        });
        await settleAsyncWork();
        notifications = 0;

        gamesListener();
        await settleAsyncWork();

        expect(notifications, 0);
        expect(vm.homeTeamScore, 12);
        expect(vm.awayTeamScore, 8);

        vm.dispose();
      },
    );

    test('notifies when the updated game score changes', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 4)),
        homeScore: 12,
        awayScore: 8,
      );
      when(() => mockGamesViewModel.findGame(currentGame.dbkey)).thenAnswer(
        (_) async => buildGame(
          startTimeUTC: currentGame.startTimeUTC,
          homeScore: 14,
          awayScore: 8,
        ),
      );

      final vm = GameTipViewModel(
        tipper,
        currentComp,
        currentGame,
        mockTipsViewModel,
        database: mockDb,
      );
      var notifications = 0;
      vm.addListener(() {
        notifications++;
      });
      await settleAsyncWork();
      notifications = 0;

      gamesListener();
      await settleAsyncWork();

      expect(notifications, 1);
      expect(vm.homeTeamScore, 14);
      expect(vm.awayTeamScore, 8);

      vm.dispose();
    });

    test(
      'notifies when live scores mutate the current game in place',
      () async {
        final currentGame = buildGame(
          startTimeUTC: DateTime.now().toUtc().subtract(
            const Duration(hours: 1),
          ),
          homeScore: null,
          awayScore: null,
        );
        when(() => mockGamesViewModel.findGame(currentGame.dbkey))
            .thenAnswer((_) async => currentGame);

        final vm = GameTipViewModel(
          tipper,
          currentComp,
          currentGame,
          mockTipsViewModel,
          database: mockDb,
        );
        var notifications = 0;
        vm.addListener(() {
          notifications++;
        });
        await settleAsyncWork();
        notifications = 0;

        currentGame.scoring!.crowdSourcedScores = [
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.home,
            tipper.dbkey!,
            6,
            false,
          ),
          CrowdSourcedScore(
            DateTime.now().toUtc(),
            ScoringTeam.away,
            tipper.dbkey!,
            4,
            false,
          ),
        ];
        gamesListener();
        await settleAsyncWork();

        expect(notifications, 1);
        expect(vm.homeTeamScore, 6);
        expect(vm.awayTeamScore, 4);

        vm.dispose();
      },
    );

    test('syncs fixture scoring onto a tip loaded with a stale game', () async {
      final scoredGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 4)),
        homeScore: 14,
        awayScore: 8,
      );
      final staleTipGame = buildGame(
        startTimeUTC: scoredGame.startTimeUTC,
        homeScore: null,
        awayScore: null,
      );
      final staleTip = Tip(
        dbkey: scoredGame.dbkey,
        game: staleTipGame,
        tipper: tipper,
        tip: GameResult.b,
        submittedTimeUTC: DateTime.now().toUtc(),
      );
      when(() => mockTipsViewModel.findTip(any(), any()))
          .thenAnswer((_) async => staleTip);

      final vm = GameTipViewModel(
        tipper,
        currentComp,
        scoredGame,
        mockTipsViewModel,
        database: mockDb,
      );
      await settleAsyncWork();

      expect(vm.tip?.game.scoring, same(scoredGame.scoring));
      expect(vm.tip?.getMaxPointsCalculated(), 2);

      vm.dispose();
    });

    test('does not notify when the streamed tip only differs by dbkey or milliseconds', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
        homeScore: 0,
        awayScore: 0,
      );
      final optimisticTipTime = DateTime.now().toUtc();
      final optimisticTip = Tip(
        game: currentGame,
        tipper: tipper,
        tip: GameResult.b,
        submittedTimeUTC: optimisticTipTime,
      );
      final streamedTip = Tip(
        dbkey: currentGame.dbkey,
        game: currentGame,
        tipper: tipper,
        tip: GameResult.b,
        submittedTimeUTC: DateTime.fromMillisecondsSinceEpoch(
          (optimisticTipTime.millisecondsSinceEpoch ~/ 1000) * 1000,
          isUtc: true,
        ),
      );

      when(() => mockGamesViewModel.findGame(currentGame.dbkey))
          .thenAnswer((_) async => currentGame);
      when(() => mockTipsViewModel.findTip(any(), any()))
          .thenAnswer((_) async => optimisticTip);

      final vm = GameTipViewModel(
        tipper,
        currentComp,
        currentGame,
        mockTipsViewModel,
        database: mockDb,
      );
      var notifications = 0;
      vm.addListener(() {
        notifications++;
      });

      await settleAsyncWork();
      expect(await vm.getTip(), optimisticTip);
      notifications = 0;

      when(() => mockTipsViewModel.findTip(any(), any()))
          .thenAnswer((_) async => streamedTip);

      tipsListener();
      await settleAsyncWork();

      expect(notifications, 0);
      expect(await vm.getTip(), optimisticTip);

      vm.dispose();
    });

    test('addTip writes the tip to RTDB without client scoring', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
        homeScore: 0,
        awayScore: 0,
      );
      final dauCompsViewModel = MockDAUCompsViewModel();
      final tippersViewModel = MockTippersViewModel();
      when(() => mockGamesViewModel.findGame(currentGame.dbkey))
          .thenAnswer((_) async => currentGame);
      when(() => dauCompsViewModel.selectedTipperTipsViewModel)
          .thenReturn(null);
      when(() => tippersViewModel.inGodMode).thenReturn(false);
      di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
      di.registerSingleton<TippersViewModel>(tippersViewModel);

      final vm = GameTipViewModel(
        tipper,
        currentComp,
        currentGame,
        mockTipsViewModel,
        database: mockDb,
        logAnalyticsEvent: (_, _) async {},
        writeTipLog: (_) async {},
      );
      await settleAsyncWork();
      final tip = Tip(
        game: currentGame,
        tipper: tipper,
        tip: GameResult.b,
        submittedTimeUTC: DateTime.utc(2030, 1, 1, 9),
      );

      await vm.addTip(tip);

      final updatePayload =
          verify(() => mockDb.update(captureAny())).captured.single as Map;
      expect(
        updatePayload.keys.single,
        '/AllTips/${currentComp.dbkey}/${tipper.dbkey}/${currentGame.dbkey}',
      );
      expect(updatePayload.values.single, containsPair('r', GameResult.b.name));
      verify(() => mockTipsViewModel.waitForTipUpdate(tip)).called(1);

      vm.dispose();
    });

    test('addTip stops waiting when the server does not answer, and keeps the tip log for when it does', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
        homeScore: 0,
        awayScore: 0,
      );
      final dauCompsViewModel = MockDAUCompsViewModel();
      final tippersViewModel = MockTippersViewModel();
      when(() => mockGamesViewModel.findGame(currentGame.dbkey))
          .thenAnswer((_) async => currentGame);
      when(() => dauCompsViewModel.selectedTipperTipsViewModel)
          .thenReturn(null);
      when(() => tippersViewModel.inGodMode).thenReturn(false);
      di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
      di.registerSingleton<TippersViewModel>(tippersViewModel);

      final Completer<void> serverAnswer = Completer<void>();
      when(() => mockDb.update(any())).thenAnswer((_) => serverAnswer.future);
      var tipLogsWritten = 0;
      final vm = GameTipViewModel(
        tipper,
        currentComp,
        currentGame,
        mockTipsViewModel,
        database: mockDb,
        logAnalyticsEvent: (_, _) async {},
        writeTipLog: (_) async {
          tipLogsWritten++;
        },
        writeAcknowledgementLimit: const Duration(milliseconds: 30),
      );
      await settleAsyncWork();
      final tip = Tip(
        game: currentGame,
        tipper: tipper,
        tip: GameResult.b,
        submittedTimeUTC: DateTime.utc(2030, 1, 1, 9),
      );

      await expectLater(
        vm.addTip(tip),
        throwsA(isA<WriteNotConfirmedException>()),
      );

      expect(vm.savingTip, isFalse, reason: 'the spinner must stop');
      expect(tipLogsWritten, 0, reason: 'nothing is confirmed yet');
      verifyNever(() => mockTipsViewModel.waitForTipUpdate(any()));

      serverAnswer.complete();
      await settleAsyncWork();

      expect(
        tipLogsWritten,
        1,
        reason: 'the record of the tip is kept once the server confirms it',
      );

      vm.dispose();
    });

    test('addTip rethrows a rejection that arrives before the limit', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
        homeScore: 0,
        awayScore: 0,
      );
      final dauCompsViewModel = MockDAUCompsViewModel();
      final tippersViewModel = MockTippersViewModel();
      when(() => mockGamesViewModel.findGame(currentGame.dbkey))
          .thenAnswer((_) async => currentGame);
      when(() => dauCompsViewModel.selectedTipperTipsViewModel)
          .thenReturn(null);
      when(() => tippersViewModel.inGodMode).thenReturn(false);
      di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
      di.registerSingleton<TippersViewModel>(tippersViewModel);
      when(() => mockDb.update(any()))
          .thenAnswer((_) async => throw StateError('permission denied'));
      final vm = GameTipViewModel(
        tipper,
        currentComp,
        currentGame,
        mockTipsViewModel,
        database: mockDb,
        logAnalyticsEvent: (_, _) async {},
        writeTipLog: (_) async {},
      );
      await settleAsyncWork();

      await expectLater(
        vm.addTip(
          Tip(
            game: currentGame,
            tipper: tipper,
            tip: GameResult.b,
            submittedTimeUTC: DateTime.utc(2030, 1, 1, 9),
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(vm.savingTip, isFalse);

      vm.dispose();
    });

    group('a tip the server has not confirmed', () {
      late UnconfirmedTipsService unconfirmed;
      late Game currentGame;
      late Completer<void> serverAnswer;
      late GameTipViewModel vm;

      Tip tipOf(GameResult result) => Tip(
        game: currentGame,
        tipper: tipper,
        tip: result,
        submittedTimeUTC: DateTime.utc(2030, 1, 1, 9),
      );

      setUp(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        unconfirmed = UnconfirmedTipsService();
        currentGame = buildGame(
          startTimeUTC: DateTime.now().toUtc().add(const Duration(hours: 4)),
          homeScore: 0,
          awayScore: 0,
        );
        final dauCompsViewModel = MockDAUCompsViewModel();
        final tippersViewModel = MockTippersViewModel();
        when(() => mockGamesViewModel.findGame(currentGame.dbkey))
            .thenAnswer((_) async => currentGame);
        when(() => dauCompsViewModel.selectedTipperTipsViewModel)
            .thenReturn(null);
        when(() => tippersViewModel.inGodMode).thenReturn(false);
        di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
        di.registerSingleton<TippersViewModel>(tippersViewModel);
        serverAnswer = Completer<void>();
        when(() => mockDb.update(any())).thenAnswer((_) => serverAnswer.future);
        vm = GameTipViewModel(
          tipper,
          currentComp,
          currentGame,
          mockTipsViewModel,
          database: mockDb,
          logAnalyticsEvent: (_, _) async {},
          writeTipLog: (_) async {},
          writeAcknowledgementLimit: const Duration(milliseconds: 30),
          unconfirmedTips: unconfirmed,
        );
        await settleAsyncWork();
      });

      tearDown(() => vm.dispose());

      test('is remembered on the device while it is unconfirmed', () async {
        await expectLater(
          vm.addTip(tipOf(GameResult.b)),
          throwsA(isA<WriteNotConfirmedException>()),
        );

        final pending = await unconfirmed.pending();
        expect(pending, hasLength(1));
        expect(pending.single.gameKey, currentGame.dbkey);
        expect(pending.single.choice, GameResult.b.name);
        expect(unconfirmed.notices, isEmpty);
      });

      test(
        'is remembered before the write reaches the database, so closing the '
        'app straight away loses nothing',
        () async {
          bool? rememberedWhenSent;
          when(() => mockDb.update(any())).thenAnswer((_) async {
            rememberedWhenSent = (await unconfirmed.pending()).any(
              (UnconfirmedTip tip) => tip.gameKey == currentGame.dbkey,
            );
            return serverAnswer.future;
          });

          await expectLater(
            vm.addTip(tipOf(GameResult.b)),
            throwsA(isA<WriteNotConfirmedException>()),
          );

          expect(
            rememberedWhenSent,
            isTrue,
            reason: 'a record made only after the wait is lost if the app closes first',
          );
        },
      );

      test(
        'that the server confirms in time leaves nothing remembered',
        () async {
          when(() => mockDb.update(any())).thenAnswer((_) async {});

          await vm.addTip(tipOf(GameResult.b));

          expect(await unconfirmed.pending(), isEmpty);
          expect(unconfirmed.notices, isEmpty);
        },
      );

      test('that the rules reject after the screen stopped waiting is reported to the user', () async {
        await expectLater(
          vm.addTip(tipOf(GameResult.b)),
          throwsA(isA<WriteNotConfirmedException>()),
        );

        serverAnswer.completeError(StateError('permission-denied'));
        await settleAsyncWork();

        expect(unconfirmed.notices, hasLength(1));
        expect(unconfirmed.notices.single, contains('not counted'));
        expect(unconfirmed.notices.single, contains('Home'));
        expect(await unconfirmed.pending(), isEmpty);
      });

      test(
        'that the server confirms late is forgotten without a notice',
        () async {
          await expectLater(
            vm.addTip(tipOf(GameResult.b)),
            throwsA(isA<WriteNotConfirmedException>()),
          );

          serverAnswer.complete();
          await settleAsyncWork();

          expect(unconfirmed.notices, isEmpty);
          expect(await unconfirmed.pending(), isEmpty);
        },
      );

      test('that is rejected before the limit is left to the screen, with no notice', () async {
        when(() => mockDb.update(any()))
            .thenAnswer((_) async => throw StateError('permission-denied'));

        await expectLater(
          vm.addTip(tipOf(GameResult.b)),
          throwsA(isA<StateError>()),
        );
        await settleAsyncWork();

        expect(unconfirmed.notices, isEmpty);
        expect(await unconfirmed.pending(), isEmpty);
      });
    });
  });
}
