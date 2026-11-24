import 'dart:math' as math;

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_banners.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_observer.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class _MockTippersViewModel extends Mock implements TippersViewModel {}

/// A page with state of its own, to show the banners never rebuild it.
class _CountingPage extends StatefulWidget {
  const _CountingPage();

  @override
  State<_CountingPage> createState() => _CountingPageState();
}

class _CountingPageState extends State<_CountingPage> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('Taps $taps'),
    ),
  );
}

void main() {
  late _MockDAUCompsViewModel comps;
  late _MockTippersViewModel tippers;
  late List<VoidCallback> listeners;

  DAUComp comp(String name) => DAUComp(
    dbkey: name,
    name: name,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: [],
  );
  final daisy = Tipper(
    dbkey: 'tipper-1',
    authuid: 'auth-1',
    email: 'tipper@example.com',
    name: 'Daisy',
    tipperRole: TipperRole.tipper,
    compsPaidFor: [],
  );

  setUp(() async {
    await di.reset();
    comps = _MockDAUCompsViewModel();
    tippers = _MockTippersViewModel();
    listeners = [];
    for (final viewModel in <ChangeNotifier>[comps, tippers]) {
      when(() => viewModel.addListener(any())).thenAnswer(
        (call) => listeners.add(call.positionalArguments.first as VoidCallback),
      );
      when(
        () => viewModel.removeListener(any()),
      ).thenAnswer((call) => listeners.remove(call.positionalArguments.first));
    }
    when(() => comps.selectedDAUComp)
        .thenReturn(comp('DAU Footy Tipping 2025'));
    when(() => comps.isSelectedCompActiveComp()).thenReturn(false);
    when(() => tippers.inGodMode).thenReturn(false);
    when(() => tippers.authenticatedTipper).thenReturn(daisy);
    when(() => tippers.selectedTipper).thenReturn(daisy);
    di
      ..registerSingleton<DAUCompsViewModel>(comps)
      ..registerSingleton<TippersViewModel>(tippers);
  });
  tearDown(() async => di.reset());

  /// A wide window showing a page opened from the tabs, which on the web is a
  /// narrow column in the middle of it.
  Future<void> openPageInWideWindow(
    WidgetTester tester, {
    EdgeInsets controlsRoom = EdgeInsets.zero,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // The nav controls tell the pages the room they take this way.
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: controlsRoom),
          child: navigator!,
        ),
        home: const SizedBox.shrink(),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(appPageRoute((_) => const _CountingPage()));
    await tester.pumpAndSettle();
  }

  void notify() {
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }

  Offset expectedCenter(double windowHeight, double innerDistance) {
    final center = (innerDistance + 6) * math.sqrt1_2;
    return Offset(center, windowHeight - center);
  }

  BoxDecoration ribbonDecoration(WidgetTester tester, String label) {
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
          .first,
    );
    return box.decoration as BoxDecoration;
  }

  double ribbonTextWidth(WidgetTester tester, String label) => tester
      .getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(SizedBox))
            .first,
      )
      .width;

  Finder ribbons() => find.descendant(
    of: find.descendant(
      of: find.byType(AppBanners),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Stack &&
            widget.fit == StackFit.expand &&
            widget.clipBehavior == Clip.hardEdge,
      ),
    ),
    matching: find.byType(Transform),
  );

  const window = Rect.fromLTWH(0, 0, 1200, 800);

  testWidgets('a past comp\'s year sits in the window\'s bottom-left corner, '
      'not the narrow page\'s', (tester) async {
    await openPageInWideWindow(tester);

    expect(tester.getRect(find.byType(AppBanners)), window);
    expect(
      tester.getCenter(find.text('2025')),
      offsetMoreOrLessEquals(expectedCenter(800, 44), epsilon: 0.1),
    );
    expect(ribbonDecoration(tester, '2025').color, Colors.orange);
    final style = tester.widget<Text>(find.text('2025')).style!;
    expect(style.color, Colors.black);
    expect(style.decoration, TextDecoration.none);
  });

  testWidgets('the banners sit at the bottom of the window even when bottom '
      'or right controls reserve room', (tester) async {
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(
      tester,
      controlsRoom: const EdgeInsets.only(bottom: 96),
    );
    expect(
      tester.getCenter(find.text('2025')),
      offsetMoreOrLessEquals(expectedCenter(800, 44), epsilon: 0.1),
    );
    expect(
      tester.getCenter(find.text('Daisy')),
      offsetMoreOrLessEquals(expectedCenter(800, 62), epsilon: 0.1),
    );

    await openPageInWideWindow(
      tester,
      controlsRoom: const EdgeInsets.only(right: 80),
    );
    expect(
      tester.getCenter(find.text('2025')),
      offsetMoreOrLessEquals(expectedCenter(800, 44), epsilon: 0.1),
    );
    expect(
      tester.getCenter(find.text('Daisy')),
      offsetMoreOrLessEquals(expectedCenter(800, 62), epsilon: 0.1),
    );
  });

  testWidgets('the banner is part of the page, so a dialog or sheet opened '
      'over it covers it', (tester) async {
    await openPageInWideWindow(tester);

    // Inside the page's route, rather than around the navigator that also
    // holds the dialogs and sheets.
    expect(
      find.ancestor(of: find.text('2025'), matching: find.byType(Navigator)),
      findsOneWidget,
    );
  });

  testWidgets('the active comp has no year banner', (tester) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);

    await openPageInWideWindow(tester);

    expect(ribbons(), findsNothing);
  });

  testWidgets('god mode is one red banner with the tipper\'s name in the '
      'outer bottom-left slot', (tester) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(tester);

    expect(ribbons(), findsOneWidget);
    expect(
      tester.getCenter(find.text('Daisy')),
      offsetMoreOrLessEquals(expectedCenter(800, 62), epsilon: 0.1),
    );
    expect(ribbonDecoration(tester, 'Daisy').color, Colors.red);
    final style = tester.widget<Text>(find.text('Daisy')).style!;
    expect(style.color, Colors.white);
    expect(style.decoration, TextDecoration.none);
  });

  testWidgets('god mode on a past comp stacks parallel above the year banner '
      'in the bottom-left corner with wider room for names', (tester) async {
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(tester);

    final yearCenter = tester.getCenter(find.text('2025'));
    final godModeCenter = tester.getCenter(find.text('Daisy'));
    expect(godModeCenter.dy, lessThan(yearCenter.dy));
    expect(godModeCenter.dx, greaterThan(yearCenter.dx));
    // Centers are 18pt apart along the 45-degree diagonal (12pt ribbon + 6pt gap).
    expect(
      (godModeCenter - yearCenter).distance,
      moreOrLessEquals(18, epsilon: 0.2),
    );
    expect(ribbonTextWidth(tester, 'Daisy'), 116);
    expect(ribbonTextWidth(tester, '2025'), 80);
    expect(
      ribbonTextWidth(tester, 'Daisy'),
      greaterThan(ribbonTextWidth(tester, '2025')),
    );
  });

  testWidgets('god mode truncates a very long tipper name on one line without '
      'overflowing', (tester) async {
    final longTipper = Tipper(
      dbkey: 'tipper-long',
      authuid: 'auth-long',
      email: 'long@example.com',
      name: 'Bartholomew Maximilian Kensington',
      tipperRole: TipperRole.tipper,
      compsPaidFor: [],
    );
    when(() => tippers.inGodMode).thenReturn(true);
    when(() => tippers.selectedTipper).thenReturn(longTipper);

    await openPageInWideWindow(tester);

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.text('Bartholomew Maximilian Kensington'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets(
    'stays clear of the floating tab pill on a narrow portrait phone',
    (tester) async {
      when(() => tippers.inGodMode).thenReturn(true);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controls = AppControlsViewModel();
      addTearDown(controls.dispose);
      final observer = AppControlsObserver(controls);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [observer],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(bottom: 34)),
            child: AppControlsHost(
              viewModel: controls,
              observer: observer,
              child: child!,
            ),
          ),
          home: AppNavTabsScope(
            viewModel: controls,
            tabs: AppNavTabs(
              destinations: const [
                AppNavDestination(
                  icon: Icon(Icons.sports_football),
                  shortLabel: 'TIPS',
                ),
                AppNavDestination(
                  icon: Icon(Icons.auto_graph),
                  shortLabel: 'STATS',
                ),
                AppNavDestination(
                  icon: Icon(Icons.person),
                  shortLabel: 'PROFILE',
                ),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            child: const AppBanners(child: Scaffold(body: Text('home'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pill = tester.getRect(find.byType(AppGlassPill));
      // Outer edge of the god-mode ribbon: x + (height - y) = (62 + 12) * sqrt(2).
      final ribbonMaxXAtPillBottom = 74 * math.sqrt2 - (852 - pill.bottom);
      expect(ribbonMaxXAtPillBottom, lessThan(pill.left));
      expect(
        tester.getCenter(find.text('2025')),
        offsetMoreOrLessEquals(expectedCenter(852, 44), epsilon: 0.1),
      );
      expect(
        tester.getCenter(find.text('Daisy')),
        offsetMoreOrLessEquals(expectedCenter(852, 62), epsilon: 0.1),
      );
    },
  );

  testWidgets('a banner coming or going leaves the page under it as it was', (
    tester,
  ) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);
    await openPageInWideWindow(tester);
    await tester.tap(find.text('Taps 0'));
    await tester.pump();

    when(() => comps.isSelectedCompActiveComp()).thenReturn(false);
    notify();
    await tester.pump();

    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Taps 1'), findsOneWidget);
  });

  testWidgets('without a signed-in tipper, god mode is not asked about', (
    tester,
  ) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);
    when(() => tippers.authenticatedTipper).thenReturn(null);
    when(() => tippers.inGodMode).thenThrow(StateError('no tipper yet'));

    await openPageInWideWindow(tester);

    expect(tester.takeException(), isNull);
    expect(ribbons(), findsNothing);
  });
}
