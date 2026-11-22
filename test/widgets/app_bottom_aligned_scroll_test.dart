import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const controlsRoom = 84.0;

  Future<void> pumpPage(WidgetTester tester, double contentHeight) {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 600),
            padding: EdgeInsets.only(bottom: controlsRoom),
          ),
          child: Scaffold(
            body: AppBottomAlignedScroll(
              child: SizedBox(
                key: const Key('content'),
                width: 300,
                height: contentHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('short content rests at the bottom, clear of the controls', (
    tester,
  ) async {
    await pumpPage(tester, 200);

    expect(
      tester.getBottomLeft(find.byKey(const Key('content'))).dy,
      600 - controlsRoom,
    );
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .maxScrollExtent,
      0,
      reason: 'nothing to scroll when it fits',
    );
  });

  testWidgets('tall content scrolls until its last row clears the controls', (
    tester,
  ) async {
    await pumpPage(tester, 900);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(
      tester.getBottomLeft(find.byKey(const Key('content'))).dy,
      600 - controlsRoom,
    );
  });
}
