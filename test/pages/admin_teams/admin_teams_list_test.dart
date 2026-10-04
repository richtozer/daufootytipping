import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';
import '../../support/load_tips_fonts.dart';

class _MockTeamsViewModel extends Mock implements TeamsViewModel {}

void main() {
  setUpAll(loadTipsFonts);

  late _MockTeamsViewModel teamsViewModel;
  late AppControlsViewModel appControls;

  setUp(() async {
    await di.reset();
    appControls = registerAppControlsViewModel();
    teamsViewModel = _MockTeamsViewModel();
    when(() => teamsViewModel.addListener(any())).thenReturn(null);
    when(() => teamsViewModel.removeListener(any())).thenReturn(null);
    when(() => teamsViewModel.teams).thenReturn([
      Team(dbkey: 'n2', name: 'Storm', league: League.nrl),
      Team(dbkey: 'a1', name: 'Crows', league: League.afl),
      Team(dbkey: 'n1', name: 'Broncos', league: League.nrl),
    ]);
  });
  tearDown(() async {
    await di.reset();
    appControls.dispose();
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithControls(appControls, home: const SizedBox.shrink()),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TeamsListPage(teamsViewModel: teamsViewModel),
          ),
        );
    await tester.pumpAndSettle();
  }

  List<String> shownTeams(WidgetTester tester) =>
      [
        for (final name in ['Broncos', 'Crows', 'Storm'])
          if (find.text(name).evaluate().isNotEmpty) name,
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );

  testWidgets('lists the teams in a table grouped by league', (tester) async {
    await openPage(tester);

    expect(find.byType(AppTable), findsOneWidget);
    // AFL before NRL, and by name within a league.
    expect(shownTeams(tester), ['Crows', 'Broncos', 'Storm']);
  });

  testWidgets('tapping the Team heading sorts by name', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    expect(shownTeams(tester), ['Broncos', 'Crows', 'Storm']);
  });
}
