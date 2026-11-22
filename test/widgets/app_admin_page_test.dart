import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_admin_page.dart';
import 'package:daufootytipping/widgets/app_bottom_aligned_scroll.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

import '../support/app_controls_test_app.dart';

void main() {
  late AppControlsViewModel appControls;

  setUp(() async {
    await di.reset();
    appControls = registerAppControlsViewModel();
  });
  tearDown(() async {
    await di.reset();
    appControls.dispose();
  });

  Future<void> openPage(
    WidgetTester tester, {
    List<AppGlassAction> actions = const [],
  }) async {
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
            builder: (_) => AppAdminPage(
              title: 'Admin Things',
              actions: actions,
              body: const Align(
                alignment: Alignment.bottomCenter,
                child: Text('rows'),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a plain title with no app bar', (tester) async {
    await openPage(tester);

    expect(find.text('Admin Things'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('offers Back, and its actions beside it', (tester) async {
    var added = 0;
    await openPage(
      tester,
      actions: [
        AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () => added++),
      ],
    );

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    expect(added, 1);
  });

  testWidgets('Back returns to the previous page', (tester) async {
    await openPage(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Admin Things'), findsNothing);
  });

  testWidgets('keeps its body above the controls', (tester) async {
    await openPage(tester);

    final bodyBottom = tester.getBottomLeft(find.text('rows')).dy;
    final controlsTop = tester.getTopLeft(find.byType(AppGlassButton)).dy;
    expect(bodyBottom, lessThanOrEqualTo(controlsTop));
  });

  Future<void> openList(WidgetTester tester, {required int rows}) async {
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
            builder: (_) => AppAdminPage(
              title: 'Admin Things',
              scrollsUnderControls: true,
              body: AppBottomAlignedScroll(
                child: Column(
                  children: [
                    for (var i = 0; i < rows; i++)
                      SizedBox(height: 56, child: Text('row $i')),
                  ],
                ),
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

  testWidgets('a long list scrolls under the controls, which fade at its end', (
    tester,
  ) async {
    await openList(tester, rows: 40);
    expect(backOpacity(tester), 1);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -20000),
    );
    await tester.pumpAndSettle();
    expect(backOpacity(tester), 0);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(backOpacity(tester), 1);
  });

  testWidgets('a short list sits above the controls and never fades them', (
    tester,
  ) async {
    await openList(tester, rows: 3);

    final controlsTop = tester.getTopLeft(find.byType(AppGlassButton)).dy;
    expect(
      tester.getBottomLeft(find.text('row 2')).dy,
      lessThanOrEqualTo(controlsTop),
    );
    expect(backOpacity(tester), 1);
  });
}
