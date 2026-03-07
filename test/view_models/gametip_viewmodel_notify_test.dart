import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTipsViewModel extends Mock implements TipsViewModel {}
class MockGamesViewModel extends Mock implements GamesViewModel {}
class MockDatabaseReference extends Mock implements DatabaseReference {}
class FakeGame extends Fake implements Game {}
class FakeTipper extends Fake implements Tipper {}

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
    });

    setUp(() {
      mockTipsViewModel = MockTipsViewModel();
      mockGamesViewModel = MockGamesViewModel();
      mockDb = MockDatabaseReference();

      when(() => mockTipsViewModel.addListener(any())).thenReturn(null);
      when(() => mockTipsViewModel.removeListener(any())).thenReturn(null);
      when(() => mockGamesViewModel.removeListener(any())).thenReturn(null);
      when(() => mockGamesViewModel.addListener(any())).thenAnswer((invocation) {
        gamesListener = invocation.positionalArguments[0] as VoidCallback;
      });

      when(() => mockTipsViewModel.gamesViewModel).thenReturn(mockGamesViewModel);
      when(() => mockTipsViewModel.initialLoadCompleted).thenAnswer((_) async {});
      when(() => mockTipsViewModel.findTip(any(), any())).thenAnswer((_) async => null);
      when(() => mockTipsViewModel.getTipsForTipper(any())).thenReturn([]);

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

    test('does not notify when the updated game scores and state are unchanged', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 4)),
        homeScore: 12,
        awayScore: 8,
      );
      when(
        () => mockGamesViewModel.findGame(currentGame.dbkey),
      ).thenAnswer((_) async => buildGame(
        startTimeUTC: currentGame.startTimeUTC,
        homeScore: 12,
        awayScore: 8,
      ));

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
    });

    test('notifies when the updated game score changes', () async {
      final currentGame = buildGame(
        startTimeUTC: DateTime.now().toUtc().subtract(const Duration(hours: 4)),
        homeScore: 12,
        awayScore: 8,
      );
      when(
        () => mockGamesViewModel.findGame(currentGame.dbkey),
      ).thenAnswer((_) async => buildGame(
        startTimeUTC: currentGame.startTimeUTC,
        homeScore: 14,
        awayScore: 8,
      ));

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
  });
}
