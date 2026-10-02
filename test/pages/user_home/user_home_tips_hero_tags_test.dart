import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/tips/adaptive_tips_card.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/load_tips_fonts.dart';

final _theme = ThemeData.localize(
  FlexThemeData.light(scheme: FlexScheme.green),
  Typography.englishLike2021,
);

/// The same team in two games, which is every team in a competition.
TipsCardDisplay _card(String gameDbKey) {
  TipsTeamDisplay team(String teamDbKey, String name) => TipsTeamDisplay(
    name,
    League.nrl.logo,
    heroTag: tipsCardHeroTag(gameDbKey: gameDbKey, teamDbKey: teamDbKey),
  );
  return TipsCardDisplay(
    id: gameDbKey,
    home: team('nrl-Broncos', 'Broncos'),
    away: team('nrl-$gameDbKey', 'Storm'),
    league: League.nrl,
    info: 'Kickoff: Fri 25 Sep 19:50',
  );
}

void main() {
  setUpAll(loadTipsFonts);

  testWidgets('one team in two cards does not collide on push', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cards = [_card('round-1'), _card('round-2')];
    final layout = TipsCardLayout.measure(
      width: 900,
      textScaler: const TextScaler.linear(1),
      textTheme: _theme.textTheme,
      textDirection: TextDirection.ltr,
      cards: [for (final card in cards) card.content(_theme.textTheme)],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final card in cards)
                  AdaptiveTipsCard(
                    data: card,
                    layout: layout,
                    activePanel: TipsPanel.tips,
                    onPanelChanged: (_) {},
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(body: Text('detail')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Hero), findsNWidgets(4));

    // Pushing is when the hero controller collects the outgoing route's tags.
    // Tagging by team alone put 'team_icon_nrl-Broncos' on two of these four.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  test('a screen that shows a team once keeps the plain tag', () {
    // The ladder's rows and the history page it opens hold one logo per team,
    // so they pair up on the team alone.
    expect(teamHeroTag('nrl-Broncos'), 'team_icon_nrl-Broncos');
  });
}
