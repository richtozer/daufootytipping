import 'package:daufootytipping/pages/user_home/user_home_tips.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpFooter(WidgetTester tester, double bottomPadding) {
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomPadding)),
          child: const Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 400, child: EndFooter()),
          ),
        ),
      ),
    );
  }

  testWidgets('grows by the room the floating controls take', (tester) async {
    await pumpFooter(tester, 0);
    expect(tester.getSize(find.byType(EndFooter)).height, kTipsEndFooterHeight);

    await pumpFooter(tester, 84);
    expect(
      tester.getSize(find.byType(EndFooter)).height,
      kTipsEndFooterHeight + 84,
    );
  });

  testWidgets('keeps its text where it was, at the top of the taller card', (
    tester,
  ) async {
    await pumpFooter(tester, 0);
    final before = tester.getTopLeft(find.text('End of regular competition'));

    await pumpFooter(tester, 84);
    final after = tester.getTopLeft(find.text('End of regular competition'));

    expect(after, before);
  });
}
