import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/team_logos_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';
import '../../support/load_tips_fonts.dart';

class _MockTeamsViewModel extends Mock implements TeamsViewModel {}

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockGamesViewModel extends Mock implements GamesViewModel {}

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="#000"/></svg>';

void main() {
  setUpAll(loadTipsFonts);

  late _MockTeamsViewModel teamsViewModel;
  late _MockGamesViewModel gamesViewModel;
  late AppControlsViewModel appControls;

  setUp(() async {
    await di.reset();
    appControls = registerAppControlsViewModel();
    teamsViewModel = _MockTeamsViewModel();
    when(() => teamsViewModel.addListener(any())).thenReturn(null);
    when(() => teamsViewModel.removeListener(any())).thenReturn(null);
    when(() => teamsViewModel.teams).thenReturn([
      Team(dbkey: 'nrl-Storm', name: 'Storm', league: League.nrl),
      Team(dbkey: 'afl-Crows', name: 'Crows', league: League.afl),
      Team(dbkey: 'nrl-Broncos', name: 'Broncos', league: League.nrl),
      Team(dbkey: 'afl-1st', name: '1st', league: League.afl),
      Team(
        dbkey: 'nrl-to be announced',
        name: 'To be announced',
        league: League.nrl,
      ),
    ]);
    gamesViewModel = _MockGamesViewModel();
    // Counted from every comp's stored games: the placeholders play in one
    // round or none, so they are not here.
    when(() => gamesViewModel.teamKeysInSeveralRoundsOfAnyComp())
        .thenAnswer((_) async => {'nrl-Storm', 'afl-Crows', 'nrl-Broncos'});
    final comps = _MockDAUCompsViewModel();
    when(() => comps.gamesViewModel).thenReturn(gamesViewModel);
    di
      ..registerSingleton<TeamsViewModel>(teamsViewModel)
      ..registerSingleton<DAUCompsViewModel>(comps)
      ..registerSingleton<TeamLogosViewModel>(
        TeamLogosViewModel(
          source: () => Stream.value({
            'nrl-Storm': {teamLogoSvgKey: _svg},
          }),
        ),
      );
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
        .push(MaterialPageRoute<void>(builder: (_) => const TeamsListPage()));
    await tester.pumpAndSettle();
  }

  List<String> shownTeams(WidgetTester tester) =>
      [
        for (final name in ['Broncos', 'Crows', 'Storm', '1st'])
          if (find.text(name).evaluate().isNotEmpty) name,
        if (find.text('To be announced').evaluate().isNotEmpty)
          'To be announced',
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );

  testWidgets('lists the season teams grouped by league, hiding placeholders '
      'that play in at most one round of any comp', (tester) async {
    await openPage(tester);

    expect(find.byType(AppTable), findsOneWidget);
    // AFL before NRL, and by name within a league.
    expect(shownTeams(tester), ['Crows', 'Broncos', 'Storm']);
    expect(find.text('3 of 3'), findsOneWidget);
  });

  testWidgets('tapping the Team heading sorts by name', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();

    expect(shownTeams(tester), ['Broncos', 'Crows', 'Storm']);
  });

  testWidgets('NRL and AFL start ticked, and unticking one hides its teams', (
    tester,
  ) async {
    await openPage(tester);
    final nrl = find.widgetWithText(FilterChip, 'NRL');
    expect(tester.widget<FilterChip>(nrl).selected, isTrue);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'AFL'))
          .selected,
      isTrue,
    );

    await tester.tap(nrl);
    await tester.pumpAndSettle();

    expect(shownTeams(tester), ['Crows']);
    expect(find.text('1 of 3'), findsOneWidget);
  });

  testWidgets('No logo narrows the list to teams without a logo', (
    tester,
  ) async {
    await openPage(tester);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'No logo'))
          .selected,
      isFalse,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'No logo'));
    await tester.pumpAndSettle();

    expect(shownTeams(tester), ['Crows', 'Broncos']);
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('with no games counted yet every team shows', (tester) async {
    when(() => gamesViewModel.teamKeysInSeveralRoundsOfAnyComp())
        .thenAnswer((_) async => <String>{});

    await openPage(tester);

    expect(shownTeams(tester), hasLength(5));
    expect(find.text('5 of 5'), findsOneWidget);
  });
}
