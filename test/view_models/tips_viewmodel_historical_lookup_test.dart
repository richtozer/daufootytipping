import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockGamesViewModel extends Mock implements GamesViewModel {}
class MockTippersViewModel extends Mock implements TippersViewModel {}
class MockDatabaseReference extends Mock implements DatabaseReference {}
class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  group('TipsViewModel historical lookup', () {
    late MockGamesViewModel mockGamesViewModel;
    late MockTippersViewModel mockTippersViewModel;
    late MockDatabaseReference mockDb;
    late Tipper tipper;
    late Team homeTeam;
    late Team awayTeam;
    late DAUComp currentComp;
    late DAUComp historicalComp;

    DAURound round({
      required int number,
      required DateTime start,
      required DateTime end,
    }) {
      return DAURound(
        dAUroundNumber: number,
        firstGameKickOffUTC: start,
        lastGameKickOffUTC: end,
      );
    }

    Game buildGame({
      required String dbkey,
      required DateTime startTimeUTC,
    }) {
      return Game(
        dbkey: dbkey,
        league: League.nrl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: startTimeUTC,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: Scoring(homeTeamScore: 10, awayTeamScore: 8),
      );
    }

    setUp(() {
      mockGamesViewModel = MockGamesViewModel();
      mockTippersViewModel = MockTippersViewModel();
      mockDb = MockDatabaseReference();

      when(() => mockGamesViewModel.addListener(any())).thenReturn(null);
      when(() => mockGamesViewModel.removeListener(any())).thenReturn(null);

      homeTeam = Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl);
      awayTeam = Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl);
      tipper = Tipper(
        dbkey: 'tipper-1',
        compsPaidFor: const [],
        authuid: 'auth-1',
        name: 'Tipper',
        email: 'tipper@example.com',
        tipperRole: TipperRole.tipper,
      );

      currentComp = DAUComp(
        dbkey: 'comp-2026',
        name: '2026',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl/2026'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl/2026'),
        daurounds: [
          round(
            number: 1,
            start: DateTime.parse('2026-03-01T00:00:00Z'),
            end: DateTime.parse('2026-03-31T23:59:59Z'),
          ),
        ],
      );

      historicalComp = DAUComp(
        dbkey: 'comp-2025',
        name: '2025',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl/2025'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl/2025'),
        daurounds: [
          round(
            number: 1,
            start: DateTime.parse('2025-03-01T00:00:00Z'),
            end: DateTime.parse('2025-03-31T23:59:59Z'),
          ),
        ],
      );
    });

    test('findTip does not collide with a different season using the same game key', () async {
      final vm = TipsViewModel.forTipper(
        mockTippersViewModel,
        currentComp,
        mockGamesViewModel,
        tipper,
        database: mockDb,
        listenToTips: false,
      );

      final currentSeasonGame = buildGame(
        dbkey: 'nrl-01-001',
        startTimeUTC: DateTime.parse('2026-03-10T10:00:00Z'),
      );
      final historicalSeasonGame = buildGame(
        dbkey: 'nrl-01-001',
        startTimeUTC: DateTime.parse('2025-03-10T10:00:00Z'),
      );

      vm.setTipsForTest([
        Tip(
          game: currentSeasonGame,
          tipper: tipper,
          tip: GameResult.b,
          submittedTimeUTC: DateTime.parse('2026-03-09T10:00:00Z'),
        ),
      ]);

      final result = await vm.findTip(historicalSeasonGame, tipper);

      expect(result, isNotNull);
      expect(result!.isDefaultTip(), isTrue);
      expect(result.game.startTimeUTC, historicalSeasonGame.startTimeUTC);
    });

    test('findTip preserves a submitted current-comp tip after fixture start changes', () async {
      final vm = TipsViewModel.forTipper(
        mockTippersViewModel,
        currentComp,
        mockGamesViewModel,
        tipper,
        database: mockDb,
        listenToTips: false,
      );

      final originalGame = buildGame(
        dbkey: 'nrl-01-001',
        startTimeUTC: DateTime.parse('2026-03-10T10:00:00Z'),
      );
      final rescheduledGame = buildGame(
        dbkey: 'nrl-01-001',
        startTimeUTC: DateTime.parse('2026-03-10T11:00:00Z'),
      );

      vm.setTipsForTest([
        Tip(
          game: originalGame,
          tipper: tipper,
          tip: GameResult.b,
          submittedTimeUTC: DateTime.parse('2026-03-09T10:00:00Z'),
        ),
      ]);

      final result = await vm.findTip(rescheduledGame, tipper);

      expect(result, isNotNull);
      expect(result!.isDefaultTip(), isFalse);
      expect(result.tip, GameResult.b);
      expect(result.game.startTimeUTC, rescheduledGame.startTimeUTC);
    });

    test('findTipAcrossCompetitions loads and caches a historical tip from the owning comp', () async {
      final vm = TipsViewModel.forTipper(
        mockTippersViewModel,
        currentComp,
        mockGamesViewModel,
        tipper,
        database: mockDb,
        listenToTips: false,
      );

      final historicalSeasonGame = buildGame(
        dbkey: 'nrl-01-001',
        startTimeUTC: DateTime.parse('2025-03-10T10:00:00Z'),
      );
      final historicalTipRef = MockDatabaseReference();
      final snapshot = MockDataSnapshot();
      final path =
          '${p.tipsPathRoot}/${historicalComp.dbkey}/${tipper.dbkey}/${historicalSeasonGame.dbkey}';

      when(() => mockDb.child(path)).thenReturn(historicalTipRef);
      when(() => historicalTipRef.get()).thenAnswer((_) async => snapshot);
      when(() => snapshot.exists).thenReturn(true);
      when(() => snapshot.value).thenReturn({
        'r': GameResult.b.name,
        't': 1740823200,
      });

      final firstResult = await vm.findTipAcrossCompetitions(
        historicalSeasonGame,
        tipper,
        [currentComp, historicalComp],
      );
      final secondResult = await vm.findTipAcrossCompetitions(
        historicalSeasonGame,
        tipper,
        [currentComp, historicalComp],
      );

      expect(firstResult, isNotNull);
      expect(firstResult!.isDefaultTip(), isFalse);
      expect(firstResult.tip, GameResult.b);
      expect(firstResult.game.startTimeUTC, historicalSeasonGame.startTimeUTC);
      expect(secondResult?.tip, GameResult.b);
      verify(() => historicalTipRef.get()).called(1);
    });

    test('findTipAcrossCompetitions bounds historical final round by lastGameKickOffUTC and respects single-league cutoffs', () async {
      final historicalCompWithSingleCutoff = DAUComp(
        dbkey: 'comp-2025-single-cutoff',
        name: '2025 Single Cutoff',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl/2025'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl/2025'),
        nrlRegularCompEndDateUTC: DateTime.parse('2025-03-20T00:00:00Z'),
        daurounds: [
          round(
            number: 1,
            start: DateTime.parse('2025-03-01T00:00:00Z'),
            end: DateTime.parse('2025-03-31T23:59:59Z'),
          ),
        ],
      );

      final vm = TipsViewModel.forTipper(
        mockTippersViewModel,
        currentComp,
        mockGamesViewModel,
        tipper,
        database: mockDb,
        listenToTips: false,
      );

      final aflHome = Team(
        dbkey: 'afl-home',
        name: 'AFL H',
        league: League.afl,
      );
      final aflAway = Team(
        dbkey: 'afl-away',
        name: 'AFL A',
        league: League.afl,
      );

      // Current-season game well after 2025's stored final-round end must NOT query historical comp.
      final currentSeasonAflGame = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: aflHome,
        awayTeam: aflAway,
        location: 'MCG',
        startTimeUTC: DateTime.parse('2026-03-10T10:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: Scoring(homeTeamScore: 80, awayTeamScore: 70),
      );

      final resAfterEnd = await vm.findTipAcrossCompetitions(
        currentSeasonAflGame,
        tipper,
        [historicalCompWithSingleCutoff],
      );
      expect(resAfterEnd?.isDefaultTip(), isTrue);
      verifyNever(() => mockDb.child(any()));

      // AFL game inside 2025 final round (no AFL cutoff, only NRL cutoff exists) still belongs to historical comp.
      final historicalAflGame = Game(
        dbkey: 'afl-01-002',
        league: League.afl,
        homeTeam: aflHome,
        awayTeam: aflAway,
        location: 'MCG',
        startTimeUTC: DateTime.parse('2025-03-25T10:00:00Z'),
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 2,
        scoring: Scoring(homeTeamScore: 80, awayTeamScore: 70),
      );
      final histRef = MockDatabaseReference();
      final histSnap = MockDataSnapshot();
      final histPath =
          '${p.tipsPathRoot}/${historicalCompWithSingleCutoff.dbkey}/${tipper.dbkey}/${historicalAflGame.dbkey}';
      when(() => mockDb.child(histPath)).thenReturn(histRef);
      when(() => histRef.get()).thenAnswer((_) async => histSnap);
      when(() => histSnap.exists).thenReturn(true);
      when(() => histSnap.value)
          .thenReturn({'r': GameResult.a.name, 't': 1742800000});

      final resWithinEnd = await vm.findTipAcrossCompetitions(
        historicalAflGame,
        tipper,
        [historicalCompWithSingleCutoff],
      );
      expect(resWithinEnd?.isDefaultTip(), isFalse);
      expect(resWithinEnd?.tip, GameResult.a);
    });
  });
}
