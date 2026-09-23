import 'package:carousel_slider/carousel_controller.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/league_ladder.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import '../../support/load_tips_fonts.dart';

class _GameModel extends Mock implements GameTipViewModel {}
class _Comps extends Mock implements DAUCompsViewModel {}
class _Tips extends Mock implements TipsViewModel {}
class _Tipper extends Mock implements Tipper {}
class _Comp extends Mock implements DAUComp {}

void main() {
  setUpAll(loadTipsFonts);
  testWidgets('unchanged standard card visual baseline', (tester) async {
    await di.reset();
    addTearDown(di.reset);
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final comps = _Comps();
    when(() => comps.leagueLadderRevision).thenReturn(revision);
    when(() => comps.getOrCalculateLeagueLadder(League.nrl))
        .thenAnswer((_) async => LeagueLadder(league: League.nrl, teams: []));
    di.registerSingleton<DAUCompsViewModel>(comps);
    final game = Game(
      dbkey: 'baseline', league: League.nrl,
      homeTeam: Team(dbkey: 'home', name: 'Dragons', league: League.nrl),
      awayTeam: Team(dbkey: 'away', name: 'Eels', league: League.nrl),
      location: 'Test Oval', startTimeUTC: DateTime.utc(2099),
      fixtureRoundNumber: 27, fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 0, awayTeamScore: 0),
    );
    final model = _GameModel();
    when(() => model.game).thenReturn(game);
    when(() => model.tip).thenReturn(null);
    when(() => model.savingTip).thenReturn(false);
    when(() => model.controller).thenReturn(CarouselSliderController());
    await tester.pumpWidget(MaterialApp(
      theme: FlexThemeData.light(scheme: FlexScheme.green),
      home: Provider<StatsViewModel?>.value(
        value: null,
        child: Scaffold(body: Center(child: RepaintBoundary(
          key: const Key('baseline'),
          child: SizedBox(width: 390, height: 128, child: GameListItem(
            game: game, currentTipper: _Tipper(), currentDAUComp: _Comp(),
            allTipsViewModel: _Tips(), isPercentStatsPage: false,
            gameTipViewModel: model,
          )),
        ))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(const Key('baseline')),
        matchesGoldenFile('goldens/tips-standard-390.png'));
  });
}
