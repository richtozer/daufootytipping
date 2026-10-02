import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_card_adapter.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/tips/tips_card_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/load_tips_fonts.dart';

const double _wideDisplay = 2000;

Game _game({Scoring? scoring, String location = 'Stadium Australia'}) => Game(
  dbkey: 'game-1',
  league: League.nrl,
  homeTeam: Team(dbkey: 'home-1', name: 'Rabbitohs', league: League.nrl),
  awayTeam: Team(dbkey: 'away-1', name: 'Bulldogs', league: League.nrl),
  location: location,
  startTimeUTC: DateTime.utc(2026, 9, 25, 9, 50),
  fixtureRoundNumber: 27,
  fixtureMatchNumber: 1,
  scoring: scoring,
);

List<DAURound> _rounds({
  Scoring? scoring,
  String location = 'Stadium Australia',
}) {
  final game = _game(scoring: scoring, location: location);
  return [
    DAURound(
      dAUroundNumber: 27,
      firstGameKickOffUTC: game.startTimeUTC,
      lastGameKickOffUTC: game.startTimeUTC,
      games: [game],
    ),
  ];
}

void main() {
  setUpAll(loadTipsFonts);

  testWidgets('a wide display is capped at the inline width, not filled', (
    tester,
  ) async {
    late double capped;
    late double available;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            available = _wideDisplay;
            capped = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: _rounds(),
              availableWidth: available,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      capped,
      lessThan(available),
      reason: 'a 2000px display is not filled',
    );
    expect(capped, greaterThan(500), reason: 'wider than the old fixed cap');
  });

  testWidgets('the card lays out inline at exactly the width it is given', (
    tester,
  ) async {
    late TipsCardMode modeAtCap;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final rounds = _rounds();
            final capped = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: rounds,
              availableWidth: _wideDisplay,
            );
            final textTheme = Theme.of(context).textTheme;
            modeAtCap = TipsCardLayout.measure(
              width: capped,
              textScaler: MediaQuery.textScalerOf(context),
              textTheme: textTheme,
              textDirection: Directionality.of(context),
              cards: [
                for (final card in tipsMeasurementCards(rounds))
                  card.content(textTheme),
              ],
            ).mode;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // One measurement, not two: the app must never sit at its own maximum
    // width and still render a stacked or standard card.
    expect(modeAtCap, TipsCardMode.wide);
  });

  testWidgets('a score arriving mid-round does not move the width', (
    tester,
  ) async {
    late double before;
    late double after;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            before = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: _rounds(),
              availableWidth: _wideDisplay,
            );
            after = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: _rounds(
                scoring: Scoring(homeTeamScore: 124, awayTeamScore: 8),
              ),
              availableWidth: _wideDisplay,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(after, before);
  });

  testWidgets('a pushed detail page keeps the tab width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(
              context,
            ).push<void>(appPageRoute<void>((context) => const Text('detail'))),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget);
    // Detail pages are pushed as siblings of the home route, so they are
    // outside the tabs' own bound and need the route to carry it.
    expect(
      find.ancestor(
        of: find.text('detail'),
        matching: find.byType(AppContentWidth),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a page measures and renders at one width in landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late double measured;
    late double rendered;
    late double renderedHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          // A landscape phone reports its notch on both sides.
          data: const MediaQueryData(
            size: Size(932, 430),
            padding: EdgeInsets.only(left: 62, right: 62, bottom: 21),
          ),
          child: AppPageWidth(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Pages measure their cards out here, against the width the
                // route hands them...
                measured = constraints.maxWidth;
                return Scaffold(
                  body: SafeArea(
                    child: LayoutBuilder(
                      builder: (context, inner) {
                        // ...and lay them out in here.
                        rendered = inner.maxWidth;
                        renderedHeight = inner.maxHeight;
                        return const SizedBox.expand(key: Key('body'));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The route already held the content clear of the side insets. When it
    // left them in the MediaQuery as well, this SafeArea spent them again and
    // the two widths differed by 124 -- enough to overflow a card measured
    // against the first and built to the second.
    expect(rendered, measured);
    // Spent once, not zero times: the content still clears both notches. The
    // band is narrower than the gap between them because the route also caps
    // it at the width a game card needs.
    final body = tester.getRect(find.byKey(const Key('body')));
    expect(body.left, greaterThanOrEqualTo(62));
    expect(body.right, lessThanOrEqualTo(932 - 62));
    // Only the horizontal insets are spent; the home indicator still owns its
    // strip along the bottom.
    expect(renderedHeight, 430 - 21);
  });

  testWidgets('a longer venue does widen it', (tester) async {
    late double short;
    late double long;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            short = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: _rounds(location: 'The Oval'),
              availableWidth: _wideDisplay,
            );
            long = AppContentWidth.maxContentWidth(
              context: context,
              daurounds: _rounds(
                location: 'A Very Long Regional Stadium Name Indeed',
              ),
              availableWidth: _wideDisplay,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      long,
      greaterThanOrEqualTo(short),
      reason: 'the bound is derived from competition content',
    );
  });
}
