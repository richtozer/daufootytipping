import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_round_leagueheader_listtile.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}

class MockTipsViewModel extends Mock implements TipsViewModel {}

void main() {
  testWidgets('masks rank change when no game has a known result', (
    tester,
  ) async {
    await _pumpHeader(
      tester,
      hasScoredGame: false,
      rank: 1,
      rankChange: 4,
    );

    expect(find.text('Rank: ?  '), findsOneWidget);
    expect(find.text('Rank: 1  '), findsNothing);
    expect(find.byIcon(Icons.sync_alt), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.text('?'), findsOneWidget);
    expect(find.text('4'), findsNothing);
  });

  for (final testCase
      in <({String description, int rankChange, IconData icon, Color color})>[
        (
          description: 'positive',
          rankChange: 4,
          icon: Icons.arrow_upward,
          color: Colors.green,
        ),
        (
          description: 'negative',
          rankChange: -4,
          icon: Icons.arrow_downward,
          color: Colors.red,
        ),
        (
          description: 'unchanged',
          rankChange: 0,
          icon: Icons.sync_alt,
          color: Colors.green,
        ),
      ]) {
    testWidgets('shows ${testCase.description} rank change after scoring', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        hasScoredGame: true,
        rank: 3,
        rankChange: testCase.rankChange,
      );

      expect(find.text('Rank: 3  '), findsOneWidget);
      expect(find.text('${testCase.rankChange}'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(testCase.icon));
      expect(icon.color, testCase.color);
      expect(find.text('?'), findsNothing);
    });
  }
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required bool hasScoredGame,
  required int rank,
  required int rankChange,
}) async {
  final now = DateTime.now().toUtc();
  final game = Game(
    dbkey: 'nrl-01-001',
    league: League.nrl,
    homeTeam: Team(dbkey: 'home', name: 'Home', league: League.nrl),
    awayTeam: Team(dbkey: 'away', name: 'Away', league: League.nrl),
    location: 'Test Oval',
    startTimeUTC: now.subtract(
      Duration(hours: hasScoredGame ? 3 : 1),
    ),
    fixtureRoundNumber: 1,
    fixtureMatchNumber: 1,
    scoring: hasScoredGame
        ? Scoring(homeTeamScore: 10, awayTeamScore: 4)
        : Scoring(homeTeamScore: 0, awayTeamScore: 0),
  );
  expect(
    game.gameState,
    hasScoredGame
        ? GameState.startedResultKnown
        : GameState.startedResultNotKnown,
  );

  final round = DAURound(
    dAUroundNumber: 1,
    firstGameKickOffUTC: game.startTimeUTC,
    lastGameKickOffUTC: game.startTimeUTC,
    games: [game],
  );
  final comp = DAUComp(
    dbkey: 'comp-1',
    name: 'Test Comp',
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: [round],
  );
  final tipper = Tipper(
    dbkey: 'tipper-1',
    compsPaidFor: [comp],
    authuid: 'auth-1',
    email: 'tipper@example.com',
    name: 'Tipper',
    tipperRole: TipperRole.tipper,
  );
  final tipsViewModel = MockTipsViewModel();
  final compsViewModel = MockDAUCompsViewModel();
  final statsViewModel = MockStatsViewModel();
  final roundStats = RoundStats(
    roundNumber: 1,
    aflPoints: 0,
    aflMaxPoints: 0,
    aflMarginTips: 0,
    aflMarginUPS: 0,
    nrlPoints: 0,
    nrlMaxPoints: 0,
    nrlMarginTips: 0,
    nrlMarginUPS: 0,
    rank: rank,
    rankChange: rankChange,
    nrlTipsOutstanding: 0,
    aflTipsOutstanding: 0,
  );

  when(
    () => compsViewModel.selectedTipperTipsViewModel,
  ).thenReturn(tipsViewModel);
  when(() => compsViewModel.selectedDAUComp).thenReturn(comp);
  when(
    () => tipsViewModel.numberOfOutstandingTipsForUpcomingGamesInRoundAndLeague(
      round,
      League.nrl,
    ),
  ).thenReturn(0);
  when(
    () => tipsViewModel.numberOfMarginTipsSubmittedForRoundAndLeague(
      round,
      League.nrl,
    ),
  ).thenReturn(0);
  when(() => statsViewModel.addListener(any())).thenReturn(null);
  when(() => statsViewModel.removeListener(any())).thenReturn(null);
  when(
    () => statsViewModel.getScoringRoundStats(round, tipper),
  ).thenReturn(roundStats);

  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<StatsViewModel?>.value(
        value: statsViewModel,
        child: Scaffold(
          body: RoundLeagueHeaderListTile(
            league: League.nrl,
            logoWidth: 50,
            logoHeight: 50,
            dauRound: round,
            dauCompsViewModel: compsViewModel,
            selectedTipper: tipper,
            isPercentStatsPage: false,
          ),
        ),
      ),
    ),
  );
}
