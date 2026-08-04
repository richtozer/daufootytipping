import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/services/kickoff_refresh_scheduler.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:dau_shared/services/outstanding_tips_calculator.dart';

class MockTipsViewModel extends Mock implements TipsViewModel {}
class MockKickoffRefreshScheduler extends Mock
    implements KickoffRefreshScheduler {}
class FakeDAURound extends Fake implements DAURound {}

void main() {
  group('DAUCompsViewModel currentRoundOutstandingTipsCount', () {
    late DAUCompsViewModel vm;
    late MockTipsViewModel mockTipsViewModel;
    late MockKickoffRefreshScheduler kickoffRefreshScheduler;

    DAURound round(int number, RoundState state) {
      final r = DAURound(
        dAUroundNumber: number,
        firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
        lastGameKickOffUTC: DateTime.parse('2025-01-02T00:00:00Z'),
      );
      r.roundState = state;
      return r;
    }

    setUpAll(() {
      registerFallbackValue(FakeDAURound());
    });

    setUp(() {
      kickoffRefreshScheduler = MockKickoffRefreshScheduler();
      when(
        () => kickoffRefreshScheduler.schedule(
          kickoffTimes: any(named: 'kickoffTimes'),
          onRefresh: any(named: 'onRefresh'),
        ),
      ).thenReturn(null);
      vm = DAUCompsViewModel(
        null,
        false,
        skipInit: true,
        kickoffRefreshScheduler: kickoffRefreshScheduler,
      );
      mockTipsViewModel = MockTipsViewModel();
    });

    test('notifies listeners when the scheduled kickoff callback fires', () {
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round(1, RoundState.started)],
      );
      vm.setSelectedCompForTest(comp);
      var notificationCount = 0;
      vm.addListener(() => notificationCount++);

      vm.gamesViewModelUpdatedForTest();
      expect(notificationCount, 1);

      final captured = verify(
        () => kickoffRefreshScheduler.schedule(
          kickoffTimes: any(named: 'kickoffTimes'),
          onRefresh: captureAny(named: 'onRefresh'),
        ),
      ).captured;
      final onRefresh = captured.single as void Function();
      onRefresh();

      expect(notificationCount, 2);
    });

    test('schedules a refresh at the 48-hour badge activation boundary', () {
      final firstKickoff = DateTime.parse('2030-01-05T12:00:00Z');
      final badgeRound = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: firstKickoff,
        lastGameKickOffUTC: firstKickoff.add(const Duration(days: 2)),
      );
      vm.setSelectedCompForTest(
        DAUComp(
          dbkey: 'comp',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: <DAURound>[badgeRound],
        ),
      );

      vm.gamesViewModelUpdatedForTest();

      final captured = verify(
        () => kickoffRefreshScheduler.schedule(
          kickoffTimes: captureAny(named: 'kickoffTimes'),
          onRefresh: any(named: 'onRefresh'),
        ),
      ).captured;
      final refreshTimes = (captured.single as Iterable<DateTime> Function())();
      expect(
        refreshTimes,
        contains(
          firstKickoff.subtract(
            OutstandingTipsCalculator.appBadgeActivationLeadTime,
          ),
        ),
      );
    });

    test('returns 0 when selected comp is null', () {
      vm.selectedTipperTipsViewModel = mockTipsViewModel;

      expect(vm.currentRoundOutstandingTipsCount(), 0);
    });

    test('returns 0 when selected tipper tips view model is null', () {
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round(1, RoundState.started)],
      );
      vm.setSelectedCompForTest(comp);
      vm.selectedTipperTipsViewModel = null;

      expect(vm.currentRoundOutstandingTipsCount(), 0);
    });

    test('sums NRL and AFL outstanding tips for the current round', () {
      final round1 = round(1, RoundState.allGamesEnded);
      final round2 = round(2, RoundState.started);
      final round3 = round(3, RoundState.notStarted);
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round1, round2, round3],
      );

      vm.setSelectedCompForTest(comp);
      vm.selectedTipperTipsViewModel = mockTipsViewModel;

      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.nrl,
        ),
      ).thenReturn(2);
      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.afl,
        ),
      ).thenReturn(3);

      expect(vm.currentRoundOutstandingTipsCount(), 5);
      verify(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          round2,
          League.nrl,
        ),
      ).called(1);
      verify(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          round2,
          League.afl,
        ),
      ).called(1);
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          round3,
          League.nrl,
        ),
      );
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          round3,
          League.afl,
        ),
      );
    });

    test('returns 0 when all rounds are ended', () {
      final round1 = round(1, RoundState.allGamesEnded);
      final round2 = round(2, RoundState.allGamesEnded);
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round1, round2],
      );

      vm.setSelectedCompForTest(comp);
      vm.selectedTipperTipsViewModel = mockTipsViewModel;

      expect(vm.currentRoundOutstandingTipsCount(), 0);
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.nrl,
        ),
      );
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.afl,
        ),
      );
    });

    test('clamps negative totals to zero', () {
      final round1 = round(1, RoundState.notStarted);
      final comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [round1],
      );

      vm.setSelectedCompForTest(comp);
      vm.selectedTipperTipsViewModel = mockTipsViewModel;

      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.nrl,
        ),
      ).thenReturn(-2);
      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.afl,
        ),
      ).thenReturn(-1);

      expect(vm.currentRoundOutstandingTipsCount(), 0);
    });

    test('app badge stays off until 48 hours before the next round', () {
      final now = DateTime.parse('2030-01-01T12:00:00Z');
      final nextRound = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.add(const Duration(hours: 49)),
        lastGameKickOffUTC: now.add(const Duration(days: 3)),
      );
      vm.setSelectedCompForTest(
        DAUComp(
          dbkey: 'comp',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: <DAURound>[nextRound],
        ),
      );
      vm.selectedTipperTipsViewModel = mockTipsViewModel;

      expect(vm.appBadgeOutstandingTipsCount(now), 0);
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.nrl,
        ),
      );
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          any(),
          League.afl,
        ),
      );
    });

    test('app badge uses the next round inside its 48-hour window', () {
      final now = DateTime.parse('2030-01-01T12:00:00Z');
      final previousRound = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 4)),
        lastGameKickOffUTC: now.subtract(const Duration(days: 3)),
      )..roundState = RoundState.started;
      final nextRound = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now.add(const Duration(hours: 48)),
        lastGameKickOffUTC: now.add(const Duration(days: 3)),
      );
      vm.setSelectedCompForTest(
        DAUComp(
          dbkey: 'comp',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: <DAURound>[previousRound, nextRound],
        ),
      );
      vm.selectedTipperTipsViewModel = mockTipsViewModel;
      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          nextRound,
          League.nrl,
        ),
      ).thenReturn(2);
      when(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          nextRound,
          League.afl,
        ),
      ).thenReturn(3);

      expect(vm.appBadgeOutstandingTipsCount(now), 5);
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          previousRound,
          League.nrl,
        ),
      );
      verifyNever(
        () => mockTipsViewModel
            .numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
          previousRound,
          League.afl,
        ),
      );
    });
  });
}
