import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../mocks/mock_daucomps_viewmodel.dart';
import '../../support/app_controls_test_app.dart';

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;

  setUp(() async {
    await di.reset();
    registerAppControlsViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(null);
    when(() => dauCompsViewModel.activeDAUComp).thenReturn(null);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('points tippers to the support site when no comp is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );

    expect(
      find.text('Nothing to see here.\nContact support: ${p.supportUrl}.'),
      findsOneWidget,
    );
  });

  testWidgets('before any game has a final score the page says the breakdown '
      'is coming instead of showing nothing', (tester) async {
    final comp = DAUComp(
      dbkey: 'comp-2027',
      name: 'DAU 2027',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: [],
    );
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);
    when(() => dauCompsViewModel.statsViewModel).thenReturn(null);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    // A phone held upright, where the page shows its title.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );
    await tester.pump();

    expect(find.text('Tipping breakdown coming soon'), findsOneWidget);
    expect(find.text('Percentage Tipped'), findsOneWidget);
  });
}
