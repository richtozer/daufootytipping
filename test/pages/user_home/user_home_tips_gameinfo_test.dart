import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gameinfo.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGameTipViewModel extends Mock implements GameTipViewModel {}

void main() {
  late MockGameTipViewModel mockGameTipViewModel;
  late Game game;

  setUp(() {
    mockGameTipViewModel = MockGameTipViewModel();

    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Test Oval',
      startTimeUTC: DateTime.now().toUtc().add(const Duration(days: 1)),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 0, awayTeamScore: 0),
    );

    when(() => mockGameTipViewModel.tip).thenReturn(null);
    when(() => mockGameTipViewModel.game).thenReturn(game);
  });

  testWidgets('fills the full available height', (tester) async {
    const height = 120.0;
    const width = 320.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: height,
              width: width,
              child: GameInfo(game, mockGameTipViewModel),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(Card)), const Size(width, height));
  });
}
