import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/user_home/user_home_stats.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockDAUComp extends Mock implements DAUComp {}

void main() {
  Future<Color?> panelColour(WidgetTester tester, Brightness brightness) async {
    final comp = _MockDAUComp();
    when(comp.firstNotEndedRoundNumber).thenReturn(27);
    when(() => comp.name).thenReturn('DAU Footy Tipping 2026');
    final viewModel = _MockDAUCompsViewModel();
    when(() => viewModel.selectedDAUComp).thenReturn(comp);
    when(() => viewModel.addListener(any())).thenReturn(null);
    when(() => viewModel.removeListener(any())).thenReturn(null);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(platformBrightness: brightness),
        child: ChangeNotifierProvider<DAUCompsViewModel>.value(
          value: viewModel,
          child: const MaterialApp(home: Scaffold(body: StatsTab())),
        ),
      ),
    );
    final panel = find
        .ancestor(
          of: find.text('Competition Leaderboard\nWhat did others tip?'),
          matching: find.byType(Card),
        )
        .last;
    return tester.widget<Card>(panel).color;
  }

  testWidgets('the stats panel is far more transparent in dark mode', (
    tester,
  ) async {
    final light = await panelColour(tester, Brightness.light);
    final dark = await panelColour(tester, Brightness.dark);

    expect(light, kPanelLightColor);
    expect(dark, kPanelDarkColor);
    expect(dark!.a, lessThan(light!.a / 2));
  });

  testWidgets('heads the page with the competition name', (tester) async {
    await panelColour(tester, Brightness.light);

    expect(find.text('DAU Footy Tipping 2026'), findsOneWidget);
    expect(
      find.text('Competition'),
      findsNothing,
      reason: 'the name stands alone',
    );
  });

  testWidgets(
    'each row is its own see-through card, floating on the backdrop',
    (tester) async {
      await panelColour(tester, Brightness.dark);

      final rows = [
        'Competition Leaderboard\nWhat did others tip?',
        'Round winners\nRound Leaderboards',
        'Missing Tips - Round 27',
        'NRL Ladder\nTeam rankings',
      ];
      for (final label in rows) {
        final card = tester.widget<Card>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Card))
              .first,
        );
        expect(card.color, kPanelDarkColor, reason: label);
      }
      // No panel behind them: only the header and the rows are cards.
      expect(find.byType(Card), findsNWidgets(1 + 6));
    },
  );
}
