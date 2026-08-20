import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_page.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;
  late ValueNotifier<int> ladderRevision;
  late LeagueLadder currentLadder;

  LeagueLadder ladder(String firstTeam, String secondTeam) {
    return LeagueLadder(
      league: League.nrl,
      teams: <LadderTeam>[
        LadderTeam(dbkey: 'first', teamName: firstTeam, originalRank: 1),
        LadderTeam(dbkey: 'second', teamName: secondTeam, originalRank: 2),
      ],
    );
  }

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    dauCompsViewModel = MockDAUCompsViewModel();
    ladderRevision = ValueNotifier<int>(0);
    currentLadder = ladder('Original Leader', 'Original Runner-up');

    final selectedComp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(selectedComp);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(
      () => dauCompsViewModel.leagueLadderRevision,
    ).thenReturn(ladderRevision);
    when(
      () => dauCompsViewModel.getOrCalculateLeagueLadder(
        League.nrl,
        forceRecalculate: any(named: 'forceRecalculate'),
      ),
    ).thenAnswer((_) async => currentLadder);
    when(
      () => dauCompsViewModel.getLeagueLadderAvailability(League.nrl),
    ).thenReturn(LeagueLadderAvailability.ready);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('refreshes an open ladder when fixture scores invalidate it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LeagueLadderPage(league: League.nrl)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Original Leader'), findsOneWidget);
    expect(find.text('Original Runner-up'), findsOneWidget);

    currentLadder = ladder('Updated Leader', 'Updated Runner-up');
    ladderRevision.value++;

    await tester.pump();
    await tester.pump();

    expect(find.text('Updated Leader'), findsOneWidget);
    expect(find.text('Updated Runner-up'), findsOneWidget);
    expect(find.text('Original Leader'), findsNothing);
    expect(find.text('Original Runner-up'), findsNothing);
  });
}
