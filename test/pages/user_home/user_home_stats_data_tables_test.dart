import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/scoring_roundwinners.dart';
import 'package:daufootytipping/models/scoring_leaderboard.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/team_game_history_item.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_league_ladder_historical.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_compleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundgamescoresfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundleaderboard.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundmissingtipsstats.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundpointsfortipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats_roundwinners.dart';
import 'package:daufootytipping/pages/user_home/user_home_team_games_history_page.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/load_tips_fonts.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class MockTeamsViewModel extends Mock implements TeamsViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}
class MockTableTipsViewModel extends Mock implements TipsViewModel {}

void main() {
  setUpAll(() => loadTipsFonts(includeFallbacks: true));
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockGamesViewModel gamesViewModel;
  late MockStatsViewModel statsViewModel;
  late MockTeamsViewModel teamsViewModel;
  late MockTippersViewModel tippersViewModel;
  late DAUComp selectedComp;
  late Team homeTeam;
  late Team awayTeam;
  late Tipper selectedTipper;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    dauCompsViewModel = MockDAUCompsViewModel();
    gamesViewModel = MockGamesViewModel();
    statsViewModel = MockStatsViewModel();
    teamsViewModel = MockTeamsViewModel();
    tippersViewModel = MockTippersViewModel();

    selectedComp = DAUComp(
      dbkey: 'comp-2026',
      name: 'Test Competition 2026',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[],
    );
    homeTeam = Team(dbkey: 'nrl-home', name: 'Home Team', league: League.nrl);
    awayTeam = Team(dbkey: 'nrl-away', name: 'Away Team', league: League.nrl);
    selectedTipper = Tipper(
      dbkey: 'tipper-1',
      compsPaidFor: <DAUComp>[],
      authuid: 'auth-1',
      email: 'tipper@example.com',
      name: 'Test Tipper',
      tipperRole: TipperRole.tipper,
    );

    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(selectedComp);
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);
    when(() => dauCompsViewModel.gamesViewModel).thenReturn(null);

    when(() => statsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => statsViewModel.removeListener(any())).thenAnswer((_) {});
    when(() => statsViewModel.compLeaderboard).thenReturn(<LeaderboardEntry>[]);
    when(() => statsViewModel.getRoundLeaderBoard(any())).thenReturn({});
    when(() => statsViewModel.roundWinners).thenReturn({});
    when(() => statsViewModel.getTipperRoundPointsForComp(selectedTipper))
        .thenReturn([]);
    when(() => statsViewModel.hasLiveScoresInUse).thenReturn(false);
    when(() => statsViewModel.sortRoundWinnersByRoundNumber(any()))
        .thenAnswer((_) {});

    when(() => tippersViewModel.selectedTipper).thenReturn(selectedTipper);

    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
    di.registerSingleton<StatsViewModel>(statsViewModel);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  Map<Tipper, RoundStats> populateRound() {
    final data = <Tipper, RoundStats>{};
    for (var i = 0; i < 24; i++) {
      final tipper = i == 0
          ? selectedTipper
          : Tipper(
              dbkey: 'member-$i',
              compsPaidFor: <DAUComp>[],
              authuid: 'auth-member-$i',
              email: 'member-$i@example.com',
              name: i == 1 ? 'Alexandra Long Tipper Name' : 'Member $i',
              tipperRole: TipperRole.tipper,
            );
      data[tipper] = RoundStats.fromJson({
        'aS': 24 - i,
        'nS': 30 - i,
        'aMt': i % 4,
        'nMt': i % 3,
        'aMu': i % 2,
        'nMu': i % 3,
      })..rank = i + 1;
    }
    when(() => statsViewModel.getRoundLeaderBoard(any()))
        .thenAnswer((_) => data);
    return data;
  }

  Future<void> pumpRound(
    WidgetTester tester, {
    double width = 360,
    double scale = 1,
    int round = 1,
    Widget? page,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const Key('round-page'),
          child: page ?? StatRoundLeaderboard(round),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('round leaderboard golden $width/$scale', (tester) async {
        populateRound();
        await pumpRound(tester, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const Key('round-page')),
          matchesGoldenFile(
            'goldens/round-leaderboard-${width.toInt()}-$scale.png',
          ),
        );
      });
    }
  }

  testWidgets(
    'round rows survive resize and unchanged ticks, refresh changed values',
    (tester) async {
      final data = populateRound();
      await pumpRound(tester);
      AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
      final original = table().rows;
      final listeners = verify(() => statsViewModel.addListener(captureAny()))
          .captured
          .cast<VoidCallback>();
      void notify() {
        for (final listener in listeners) {
          listener();
        }
      }

      notify();
      await tester.pump();
      expect(identical(table().rows, original), isTrue);
      await pumpRound(tester, width: 1280);
      expect(identical(table().rows, original), isTrue);
      data[selectedTipper]!.nrlPoints = 99;
      notify();
      await tester.pump();
      expect(identical(table().rows, original), isFalse);
      expect(table().rows.first.cells[3].text, '99');
      expect(
        table().rows.first.colour,
        Theme.of(tester.element(find.byType(AppTable))).highlightColor,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'round sorting preserves rank and league rules after notifications',
    (tester) async {
      populateRound();
      await pumpRound(tester, width: 768);
      AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
      expect(table().rows.first.cells.first.text, 'Test Tipper');
      await tester.tap(find.text('Rank'));
      await tester.pump();
      expect(table().rows.first.cells[1].text, '24');
      await tester.tap(find.text('NRL'));
      await tester.pump();
      expect(table().rows.first.cells[3].text, '7');
      final listeners = verify(() => statsViewModel.addListener(captureAny()))
          .captured;
      for (final listener in listeners.cast<VoidCallback>()) {
        listener();
      }
      await tester.pump();
      expect(table().rows.first.cells[3].text, '7');
      await tester.tap(find.text('Total'));
      await tester.pump();
      expect(table().rows.first.cells[1].text, '1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('whole round row opens the correct tipper and round', (
    tester,
  ) async {
    populateRound();
    await pumpRound(tester, width: 768, round: 25);
    // Tap the numeric total, not the name; the entire row is interactive.
    await tester.tap(find.text('54'));
    await tester.pumpAndSettle();
    final destination = tester.widget<StatRoundGameScoresForTipper>(
      find.byType(StatRoundGameScoresForTipper),
    );
    expect(destination.statsTipper, selectedTipper);
    expect(destination.roundNumberToDisplay, 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('round change refreshes the retained page state', (tester) async {
    populateRound();
    await pumpRound(tester);
    await pumpRound(tester, round: 2);
    verify(() => statsViewModel.getRoundLeaderBoard(2)).called(1);
    expect(find.text('Round 2 Leaderboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow round page keeps names frozen and headings pinned', (
    tester,
  ) async {
    populateRound();
    await pumpRound(tester, scale: 1.5);
    final nameX = tester.getTopLeft(find.text('Name')).dx;
    final nameY = tester.getTopLeft(find.text('Name')).dy;
    final totalX = tester.getTopLeft(find.text('Total')).dx;
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dx, nameX);
    expect(tester.getTopLeft(find.text('Total')).dx, lessThan(totalX));
    expect(tester.getRect(find.text('UPS')).right, lessThan(346));
    final vertical = tester.widget<ListView>(find.byType(ListView)).controller!;
    vertical.jumpTo(300);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dy, nameY);
    expect(tester.takeException(), isNull);
  });

  testWidgets('competition leaderboard renders its AppTable', (tester) async {
    await _expectPageRendersTable(tester, const StatCompLeaderboard());
  });

  testWidgets('round leaderboard renders its AppTable', (tester) async {
    await _expectPageRendersTable(tester, const StatRoundLeaderboard(1));
  });

  Map<int, List<RoundWinnerEntry>> populateWinners() {
    final tippers = populateRound().keys.take(2).toList();
    final winners = <int, List<RoundWinnerEntry>>{
      for (var round = 24; round >= 1; round--)
        round: [for (final tipper in tippers) RoundWinnerEntry(
          roundNumber: round, tipper: tipper, total: 54,
          nRL: 30, aFL: 24, aflMargins: 2, nrlMargins: 3,
          aflUPS: 1, nrlUPS: 2,
        )],
    };
    when(() => statsViewModel.roundWinners).thenAnswer((_) => winners);
    return winners;
  }

  for (final width in [360.0, 680.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('round winners golden $width/$scale', (tester) async {
        populateWinners();
        await pumpRound(tester, width: width, scale: scale,
          page: const StatRoundWinners());
        final table = tester.widget<AppTable>(find.byType(AppTable));
        expect(table.frozenLeading, 2);
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(const Key('round-page')),
          matchesGoldenFile('goldens/round-winners-${width.toInt()}-$scale.png'));
      });
    }
  }

  testWidgets('winners cache, grouping, sorting and navigation', (tester) async {
    final winners = populateWinners();
    await pumpRound(tester, width: 680, page: const StatRoundWinners());
    AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
    final original = table().rows;
    final listeners = verify(() => statsViewModel.addListener(captureAny())).captured.cast<VoidCallback>();
    void notify() {
      for (final listener in listeners) { listener(); }
    }
    notify();
    await tester.pump();
    expect(identical(original, table().rows), isTrue);
    await pumpRound(tester, width: 360, page: const StatRoundWinners());
    expect(identical(original, table().rows), isTrue);
    winners[24]!.first.total = 99;
    notify();
    await tester.pump();
    expect(table().rows.first.cells[2].text, '99');
    expect(table().rows[1].colour, isNot(table().rows[3].colour));
    when(() => statsViewModel.sortRoundWinnersByTotal(any())).thenAnswer((_) {});
    table().onSort!(2, true);
    await tester.pump();
    verify(() => statsViewModel.sortRoundWinnersByTotal(true)).called(1);
    expect(table().sort!.column, 2);
    // Total and name both lead to the same round leaderboard.
    table().rows.first.onTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<StatRoundLeaderboard>(find.byType(StatRoundLeaderboard))
      .roundNumberToDisplay, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('winners freeze two columns and expose UPS clear of scrollbar', (tester) async {
    populateWinners();
    await pumpRound(tester, scale: 1.5, page: const StatRoundWinners());
    final roundX = tester.getTopLeft(find.text('Round')).dx;
    final winnerX = tester.getTopLeft(find.text('Winner')).dx;
    final headerY = tester.getTopLeft(find.text('Round')).dy;
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView)).controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Round')).dx, roundX);
    expect(tester.getTopLeft(find.text('Winner')).dx, winnerX);
    expect(tester.getRect(find.text('UPS')).right, lessThanOrEqualTo(
      tester.getRect(find.byType(AppTable)).right - AppTableLayout.scrollbarLane));
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Round')).dy, headerY);
    expect(tester.takeException(), isNull);
  });

  testWidgets('round winners renders its AppTable', (tester) async {
    await _expectPageRendersTable(tester, const StatRoundWinners());
  });

  Map<Tipper, RoundStats> populateMissing() {
    final data = populateRound();
    var i = 0;
    for (final stats in data.values) {
      stats.nrlTipsOutstanding = i % 5;
      stats.aflTipsOutstanding = i % 7;
      i++;
    }
    return data;
  }

  for (final width in [360.0, 680.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('missing tips golden $width/$scale', (tester) async {
        populateMissing();
        await pumpRound(tester, width: width, scale: scale,
          page: const RoundMissingTipsStats(24));
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(const Key('round-page')),
          matchesGoldenFile('goldens/missing-tips-${width.toInt()}-$scale.png'));
      });
    }
  }

  testWidgets('missing tips filter, cache and sort refresh after notifications', (tester) async {
    final data = populateMissing();
    await pumpRound(tester, width: 680, page: const RoundMissingTipsStats(24));
    AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
    final original = table().rows;
    expect(original.every((row) => row.onTap == null), isTrue);
    expect(original.any((row) => row.cells.first.text == selectedTipper.name), isFalse);
    final listeners = verify(() => statsViewModel.addListener(captureAny())).captured.cast<VoidCallback>();
    void notify() { for (final listener in listeners) { listener(); } }
    notify();
    await tester.pump();
    expect(identical(original, table().rows), isTrue);
    await pumpRound(tester, page: const RoundMissingTipsStats(24));
    expect(identical(original, table().rows), isTrue);
    data[selectedTipper]!.nrlTipsOutstanding = 99;
    notify();
    await tester.pump();
    expect(table().rows.first.cells[1].text, '99');
    for (var column = 1; column < 4; column++) {
      for (final ascending in [true, false]) {
        table().onSort!(column, ascending);
        await tester.pump();
        notify();
        await tester.pump();
        final values = table().rows.map((row) => int.parse(row.cells[column].text!)).toList();
        final expected = List.of(values)..sort();
        expect(values, ascending ? expected : expected.reversed.toList());
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing tips keep names frozen and AFL outside scrollbar lane', (tester) async {
    populateMissing();
    await pumpRound(tester, scale: 3.2, page: const RoundMissingTipsStats(24));
    final x = tester.getTopLeft(find.text('Name')).dx;
    final y = tester.getTopLeft(find.text('Name')).dy;
    final horizontal = tester.widget<SingleChildScrollView>(find.byWidgetPredicate(
      (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal)).controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dx, x);
    expect(tester.getRect(find.text('AFL')).right, lessThanOrEqualTo(
      tester.getRect(find.byType(AppTable)).right - AppTableLayout.scrollbarLane));
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Name')).dy, y);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing tips renders its AppTable', (tester) async {
    await _expectPageRendersTable(tester, const RoundMissingTipsStats(1));
  });

  List<RoundStats> populatePoints() {
    selectedComp.daurounds.add(DAURound(dAUroundNumber: 24,
      firstGameKickOffUTC: DateTime.utc(2025), lastGameKickOffUTC: DateTime.utc(2025)));
    final points = [
      for (var round = 1; round <= 24; round++)
        RoundStats.fromJson({'nbr': round, 'aS': round, 'nS': 30 - round,
          'aMt': round % 3, 'nMt': round % 4, 'aMu': round % 2, 'nMu': round % 5}),
    ];
    when(() => statsViewModel.getTipperRoundPointsForComp(selectedTipper))
        .thenAnswer((_) => List.of(points));
    return points;
  }

  for (final width in [360.0, 680.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('round points golden $width/$scale', (tester) async {
        populatePoints();
        await pumpRound(tester, width: width, scale: scale,
          page: StatRoundPointsForTipper(selectedTipper));
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(const Key('round-page')),
          matchesGoldenFile('goldens/round-points-${width.toInt()}-$scale.png'));
      });
    }
  }

  testWidgets('round points sorting, cache and navigation survive updates', (tester) async {
    final points = populatePoints();
    await pumpRound(tester, width: 680, page: StatRoundPointsForTipper(selectedTipper));
    AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
    final original = table().rows;
    final listeners = verify(() => statsViewModel.addListener(captureAny())).captured.cast<VoidCallback>();
    void notify() { for (final listener in listeners) { listener(); } }
    notify();
    await tester.pump();
    expect(identical(original, table().rows), isTrue);
    await pumpRound(tester, page: StatRoundPointsForTipper(selectedTipper));
    expect(identical(original, table().rows), isTrue);
    points.last.nrlPoints = 99;
    notify();
    await tester.pump();
    expect(table().rows.first.cells[2].text, '99');
    for (var column = 0; column < 6; column++) {
      table().onSort!(column, true);
      await tester.pump();
      notify();
      await tester.pump();
      final values = table().rows.map((row) => int.parse(row.cells[column].text!)).toList();
      expect(values, orderedEquals(List.of(values)..sort()));
    }
    final targetRound = int.parse(table().rows.first.cells.first.text!);
    table().rows.first.onTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<StatRoundGameScoresForTipper>(
      find.byType(StatRoundGameScoresForTipper)).roundNumberToDisplay, targetRound);
    expect(tester.takeException(), isNull);
  });

  testWidgets('round points freeze the round and clear the scrollbar', (tester) async {
    populatePoints();
    await pumpRound(tester, scale: 3.2, page: StatRoundPointsForTipper(selectedTipper));
    final x = tester.getTopLeft(find.text('Round')).dx;
    final y = tester.getTopLeft(find.text('Round')).dy;
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byWidgetPredicate((widget) => widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal)).controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Round')).dx, x);
    expect(tester.getRect(find.text('UPS')).right, lessThanOrEqualTo(
      tester.getRect(find.byType(AppTable)).right - AppTableLayout.scrollbarLane));
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Round')).dy, y);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tipper round points renders its AppTable', (tester) async {
    await _expectPageRendersTable(
      tester,
      StatRoundPointsForTipper(selectedTipper),
    );
  });

  (Widget, List<Game>, MockTableTipsViewModel) populateGameScores() {
    final tips = MockTableTipsViewModel();
    when(() => tips.addListener(any())).thenAnswer((_) {});
    when(() => tips.removeListener(any())).thenAnswer((_) {});
    when(() => tips.dispose()).thenAnswer((_) {});
    when(() => tips.initialLoadCompleted).thenAnswer((_) async {});
    final games = [
      for (var i = 0; i < 20; i++) Game(
        dbkey: 'game-$i', league: i < 10 ? League.nrl : League.afl,
        homeTeam: homeTeam, awayTeam: awayTeam, location: 'Test Ground',
        startTimeUTC: DateTime.utc(2025), fixtureRoundNumber: 1, fixtureMatchNumber: i + 1,
        scoring: Scoring(homeTeamScore: 40 + i, awayTeamScore: 10),
      ),
    ];
    for (final game in games) {
      final tip = Tip(game: game, tipper: selectedTipper, tip: GameResult.a,
        submittedTimeUTC: DateTime.utc(2024));
      when(() => tips.findTip(game, selectedTipper)).thenAnswer((_) async => tip);
    }
    final round = DAURound(dAUroundNumber: 1, firstGameKickOffUTC: DateTime.utc(2025),
      lastGameKickOffUTC: DateTime.utc(2025), games: games);
    selectedComp.daurounds.add(round);
    when(() => dauCompsViewModel.gamesViewModel).thenReturn(gamesViewModel);
    when(() => dauCompsViewModel.groupGamesIntoLeagues(round)).thenAnswer((_) => {
      League.nrl: games.take(10).toList(), League.afl: games.skip(10).toList(),
    });
    return (StatRoundGameScoresForTipper(selectedTipper, 1,
      createTipsViewModel: (_, _) => tips), games, tips);
  }

  for (final width in [360.0, 680.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('round game scores golden $width/$scale', (tester) async {
        final (page, _, _) = populateGameScores();
        await pumpRound(tester, width: width, scale: scale, page: page);
        expect(find.text('40 - 10'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(const Key('round-page')),
          matchesGoldenFile('goldens/round-game-scores-${width.toInt()}-$scale.png'));
      });
    }
  }

  testWidgets('game scores retain cache and update both league results', (tester) async {
    final (page, games, tips) = populateGameScores();
    await pumpRound(tester, width: 680, page: page);
    AppTable table() => tester.widget<AppTable>(find.byType(AppTable));
    final original = table().rows;
    expect(original[1].cells[1].text, 'Home 13+ (a)');
    expect(original[12].cells[1].text, 'Home 31+ (a)');
    expect(original[1].cells.first.maxLines, 2);
    expect(original[1].cells.first.text, contains('\n40 - 10'));
    expect(table().onSort, isNull);
    expect(original.every((row) => row.onTap == null), isTrue);
    final listeners = verify(() => tips.addListener(captureAny())).captured.cast<VoidCallback>();
    for (final listener in listeners) { listener(); }
    await tester.pumpAndSettle();
    expect(identical(original, table().rows), isTrue);
    await pumpRound(tester, page: page);
    expect(identical(original, table().rows), isTrue);
    games.first.scoring!.homeTeamScore = 0;
    for (final listener in listeners) { listener(); }
    await tester.pumpAndSettle();
    expect(table().rows[1].cells.first.text, contains('\n0 - 10'));
    expect(table().rows[1].cells[1].text, 'Away (d)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('game scores freeze teams and clear max-points scrollbar lane', (tester) async {
    final (page, _, _) = populateGameScores();
    await pumpRound(tester, scale: 1.5, page: page);
    final x = tester.getTopLeft(find.text('Teams / Scores')).dx;
    final y = tester.getTopLeft(find.text('Teams / Scores')).dy;
    final horizontal = tester.widget<SingleChildScrollView>(find.byWidgetPredicate(
      (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal)).controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Teams / Scores')).dx, x);
    expect(tester.getRect(find.text('Max Points')).right, lessThanOrEqualTo(
      tester.getRect(find.byType(AppTable)).right - AppTableLayout.scrollbarLane));
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Teams / Scores')).dy, y);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tipper round games renders its AppTable', (tester) async {
    // A null competition deliberately avoids constructing a Firebase-backed
    // TipsViewModel; this smoke case only guards the table's Material ancestry.
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(null);

    await _expectPageRendersTable(
      tester,
      StatRoundGameScoresForTipper(selectedTipper, 1),
    );
  });

  testWidgets('historical matchups renders its DataTable2', (tester) async {
    final game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      location: 'Test Ground',
      startTimeUTC: DateTime.utc(2025, 5, 1),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 20, awayTeamScore: 10),
    );

    when(() => dauCompsViewModel.gamesViewModel).thenReturn(gamesViewModel);
    when(() => gamesViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => gamesViewModel.teamsViewModel).thenReturn(teamsViewModel);
    when(() => teamsViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => teamsViewModel.findTeam(homeTeam.dbkey)).thenReturn(homeTeam);
    when(() => teamsViewModel.findTeam(awayTeam.dbkey)).thenReturn(awayTeam);
    when(
      () => gamesViewModel.getCompleteMatchupHistory(
        homeTeam,
        awayTeam,
        League.nrl,
      ),
    ).thenAnswer((_) async => <Game>[game]);

    await _expectPageRendersTable(
      tester,
      LeagueLadderHistoricalMatchups(
        league: League.nrl,
        teamDbKeys: <String>[homeTeam.dbkey, awayTeam.dbkey],
      ),
      pumpAsyncState: true,
    );
  });

  testWidgets('team game history renders its DataTable2', (tester) async {
    final historyItem = TeamGameHistoryItem(
      opponentName: awayTeam.name,
      teamScore: 20,
      opponentScore: 10,
      result: 'Won',
      ladderPoints: 2,
      gameDate: DateTime.utc(2025, 5, 1),
      roundNumber: 1,
      isHomeGame: true,
    );

    when(() => dauCompsViewModel.gamesViewModel).thenReturn(gamesViewModel);
    when(() => gamesViewModel.getCompleteTeamGameHistory(homeTeam, League.nrl))
        .thenAnswer((_) async => <TeamGameHistoryItem>[historyItem]);

    await _expectPageRendersTable(
      tester,
      TeamGamesHistoryPage(team: homeTeam, league: League.nrl),
      pumpAsyncState: true,
    );
  });

  testWidgets('DataTable2 text uses the app theme, not a light fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FlexThemeData.dark(scheme: FlexScheme.green),
        home: Scaffold(
          body: DataTable2(
            columns: const <DataColumn>[DataColumn(label: Text('Tipper'))],
            rows: const <DataRow>[
              DataRow(cells: <DataCell>[DataCell(Text('Rich'))]),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final BuildContext cellTextContext = tester.element(find.text('Rich'));
    expect(
      DefaultTextStyle.of(cellTextContext).style.color,
      Theme.of(cellTextContext).textTheme.bodyMedium?.color,
    );
  });
  Future<void> pumpStatsTab(
    WidgetTester tester,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ChangeNotifierProvider<DAUCompsViewModel>.value(
          value: dauCompsViewModel,
          child: const Scaffold(body: StatsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('league ladders pair side by side on one line', (tester) async {
    await pumpStatsTab(tester, const Size(900, 1400));
    final nrl = tester.getRect(find.text('NRL Ladder\nTeam rankings'));
    final afl = tester.getRect(find.text('AFL Ladder\nTeam rankings'));
    expect(nrl.top, afl.top);
    expect(afl.left, greaterThan(nrl.right));
    // Each takes about half, so neither spans the full content width.
    expect(nrl.width, lessThan(kFormContentWidth / 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paired ladders survive a narrow pane at large text', (
    tester,
  ) async {
    await pumpStatsTab(tester, const Size(360, 900), scale: 1.5);
    expect(tester.takeException(), isNull);
    final nrl = tester.getRect(find.text('NRL Ladder\nTeam rankings'));
    final afl = tester.getRect(find.text('AFL Ladder\nTeam rankings'));
    expect(nrl.top, afl.top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats menu scrolls on a short viewport instead of overflowing', (
    tester,
  ) async {
    await pumpStatsTab(tester, const Size(900, 420));
    expect(tester.takeException(), isNull);
    final last = find.text('AFL Ladder\nTeam rankings');
    await tester.scrollUntilVisible(
      last,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats menu stays bottom aligned when the viewport is tall', (
    tester,
  ) async {
    await pumpStatsTab(tester, const Size(900, 1400));
    expect(tester.takeException(), isNull);
    // Bottom-focused layout: the final row sits near the bottom edge rather
    // than floating to the top of a tall pane.
    expect(
      tester.getRect(find.text('AFL Ladder\nTeam rankings')).bottom,
      greaterThan(1400 - 200),
    );
  });
}

Future<void> _expectPageRendersTable(
  WidgetTester tester,
  Widget page, {
  bool pumpAsyncState = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  if (pumpAsyncState) {
    await tester.pump();
    await tester.pump();
  }

  expect(tester.takeException(), isNull);
  expect(
    find.byType(page is StatRoundLeaderboard || page is StatCompLeaderboard || page is StatRoundWinners || page is StatRoundPointsForTipper || page is RoundMissingTipsStats || page is StatRoundGameScoresForTipper
        ? AppTable : DataTable2),
    findsOneWidget,
  );
}
