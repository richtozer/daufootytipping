import 'package:daufootytipping/widgets/tips/tips_team_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/load_tips_fonts.dart';

void main() {
  setUpAll(loadTipsFonts);

  const style = TextStyle(fontFamily: 'Roboto', fontSize: 16);

  Future<Text> pumpName(
    WidgetTester tester,
    String name, {
    required double height,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            height: height,
            child: TipsTeamName(TextSpan(text: name, style: style)),
          ),
        ),
      ),
    );
    return tester.widget<Text>(find.byType(Text));
  }

  testWidgets('a name that fits is never cut short', (tester) async {
    final text = await pumpName(tester, 'Bulldogs', height: 100);
    expect(text.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finals placeholder ends where the height does', (
    tester,
  ) async {
    // Three lines at this width, with room for two.
    final text = await pumpName(
      tester,
      '88th Highest-ranked WF Winner',
      height: 45,
    );
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Text)).height, lessThanOrEqualTo(45));
  });

  testWidgets('keeps one line when not even that fits', (tester) async {
    final text = await pumpName(
      tester,
      '88th Highest-ranked WF Winner',
      height: 5,
    );
    expect(text.maxLines, 1);
  });

  testWidgets('a two-line name beside a one-line one keeps its two lines', (
    tester,
  ) async {
    const twoLines = TextSpan(text: 'Western Bulldogs', style: style);
    const oneLine = TextSpan(text: 'Swans', style: style);
    // Each name has the column's width less its 4 either side.
    double needed(TextSpan text) {
      final painter = TextPainter(
        text: text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120 - 8);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    expect(needed(twoLines), greaterThan(needed(oneLine) * 1.5));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 120,
            // Just what the two names need, as the card is measured.
            height: needed(twoLines) + needed(oneLine) + 1,
            child: TipsNamesColumn(
              home: TipsNameLine.padded(twoLines),
              away: TipsNameLine.padded(oneLine),
            ),
          ),
        ),
      ),
    );

    final names = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(names.map((text) => text.maxLines), [null, null]);
    expect(tester.takeException(), isNull);
  });
}
