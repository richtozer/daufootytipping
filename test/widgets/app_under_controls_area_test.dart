import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:daufootytipping/widgets/app_under_controls_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

import '../support/app_controls_test_app.dart';
import '../support/load_tips_fonts.dart';
import 'app_table_fixture.dart';

void main() {
  setUpAll(loadTipsFonts);

  late AppControlsViewModel appControls;

  setUp(() async {
    await di.reset();
    appControls = registerAppControlsViewModel();
  });
  tearDown(() async {
    await di.reset();
    appControls.dispose();
  });

  Future<void> openTablePage(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithControls(appControls, home: const SizedBox.shrink()),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: AppUnderControlsArea(
                child: AppTable(columns: tableColumns, rows: tableRows()),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
  }

  double backOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byType(AppGlassButton),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  Future<void> scrollTable(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(ListView), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  testWidgets('a table runs under the controls rather than stopping above', (
    tester,
  ) async {
    await openTablePage(tester, const Size(390, 844));

    expect(tester.getBottomLeft(find.byType(AppTable)).dy, 844);
    expect(find.byType(AppGlassButton), findsOneWidget);
  });

  testWidgets('the controls fade at the end of the table and return on scroll '
      'up', (tester) async {
    await openTablePage(tester, const Size(390, 844));
    expect(backOpacity(tester), 1);

    await scrollTable(tester, -20000);
    expect(backOpacity(tester), 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byType(AppGlassButton),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
      reason: 'a hidden Back must not be tappable',
    );

    await scrollTable(tester, 60);
    expect(backOpacity(tester), 1);
  });

  testWidgets('a short table never fades the controls', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithControls(appControls, home: const SizedBox.shrink()),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: AppUnderControlsArea(
                child: AppTable(
                  columns: tableColumns,
                  rows: tableRows(count: 3),
                ),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(backOpacity(tester), 1);
  });

  testWidgets(
    'down the side the controls stay, as they never cover the table',
    (tester) async {
      await openTablePage(tester, const Size(844, 390));
      await scrollTable(tester, -20000);

      expect(backOpacity(tester), 1);
    },
  );
}
