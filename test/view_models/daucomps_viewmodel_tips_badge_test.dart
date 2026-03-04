import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';

class MockTipsViewModel extends Mock implements TipsViewModel {}
class FakeDAURound extends Fake implements DAURound {}

void main() {
  group('DAUCompsViewModel currentRoundOutstandingTipsCount', () {
    late DAUCompsViewModel vm;
    late MockTipsViewModel mockTipsViewModel;

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
      vm = DAUCompsViewModel(null, false, skipInit: true);
      mockTipsViewModel = MockTipsViewModel();
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
  });
}
