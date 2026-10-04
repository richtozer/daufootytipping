import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_host.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_observer.dart';
import 'package:daufootytipping/widgets/app_nav/app_controls_scopes.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_button.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_pill.dart';
import 'package:daufootytipping/widgets/app_nav/app_glass_style.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_destination.dart';
import 'package:daufootytipping/widgets/app_nav/app_nav_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = [
  AppNavDestination(
    icon: Icon(Icons.sports_rugby_outlined),
    shortLabel: 'TIPS',
  ),
  AppNavDestination(icon: Icon(Icons.auto_graph), shortLabel: 'STATS'),
];

void main() {
  late AppControlsViewModel viewModel;
  late AppControlsObserver observer;
  late List<int> selected;

  setUp(() {
    viewModel = AppControlsViewModel();
    observer = AppControlsObserver(viewModel);
    selected = [];
  });
  tearDown(() => viewModel.dispose());

  Widget homeWithTabs() => AppNavTabsScope(
    viewModel: viewModel,
    tabs: AppNavTabs(
      destinations: _destinations,
      selectedIndex: 0,
      onSelected: selected.add,
    ),
    child: const Scaffold(body: Text('home')),
  );

  Widget app(Widget home, {EdgeInsets viewInsets = EdgeInsets.zero}) {
    return MaterialApp(
      navigatorObservers: [observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: viewInsets),
        child: AppControlsHost(
          viewModel: viewModel,
          observer: observer,
          child: child!,
        ),
      ),
      home: home,
    );
  }

  Future<void> push(WidgetTester tester, Widget page) async {
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  void useView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shows the tab pill on a screen that owns the tabs', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    expect(find.byType(AppGlassPill), findsOneWidget);
    await tester.tap(find.text('STATS'));
    expect(selected, [1]);
  });

  testWidgets('shows nothing where no screen owns the tabs', (tester) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(const Scaffold(body: Text('sign in'))));
    await tester.pumpAndSettle();

    expect(find.byType(AppGlassPill), findsNothing);
    expect(find.byType(AppGlassButton), findsNothing);
  });

  testWidgets('the pill gives way to Back on a pushed page and returns', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    await push(tester, const Scaffold(body: Text('detail')));
    expect(find.byType(AppGlassPill), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byType(AppGlassButton)),
      isSemantics(label: kBackActionLabel, isButton: true, hasTapAction: true),
    );
    handle.dispose();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(AppGlassPill), findsOneWidget);
  });

  testWidgets('Back is the same size as the pill it replaces', (tester) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();
    final pill = tester.getRect(find.byType(AppGlassPill));

    await push(tester, const Scaffold(body: Text('detail')));
    final back = tester.getRect(find.byType(AppGlassButton));
    expect(back.size, const Size.square(kGlassHorizontalThickness));
    expect(back.bottom, pill.bottom, reason: 'same line along the bottom');
    expect(
      back.right,
      390 - kControlsEdgeMargin,
      reason: 'Back is in the right-hand corner, not the middle',
    );
  });

  testWidgets('centres the pill along the bottom of a tall display', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    expect(tester.getCenter(find.byType(AppGlassPill)).dx, 390 / 2);
  });

  testWidgets('keeps the side pill at the right edge, not the middle', (
    tester,
  ) async {
    useView(tester, const Size(844, 390));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.byType(AppGlassPill)).dx,
      greaterThan(844 * 0.9),
    );
  });

  testWidgets('a dialog does not summon Back', (tester) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('home'));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('sure?')),
    );
    await tester.pumpAndSettle();

    expect(find.text('sure?'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(AppGlassPill), findsOneWidget);
  });

  testWidgets('a page declares actions that sit beside Back', (tester) async {
    useView(tester, const Size(390, 844));
    var added = 0;
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    await push(
      tester,
      AppPageActions(
        viewModel: viewModel,
        actions: [
          AppGlassAction(
            icon: Icons.add,
            label: 'Add comp',
            onPressed: () => added++,
          ),
        ],
        child: const Scaffold(body: Text('admin')),
      ),
    );
    expect(find.byType(AppGlassGroup), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    expect(added, 1);
    expect(
      tester.getCenter(find.byIcon(Icons.add)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.arrow_back)).dx),
      reason: 'Back stays in the corner the pill ended in',
    );
  });

  testWidgets('a pushed-over page forgets its actions when popped', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    await push(
      tester,
      AppPageActions(
        viewModel: viewModel,
        actions: [
          AppGlassAction(icon: Icons.add, label: 'Add', onPressed: () {}),
        ],
        child: const Scaffold(body: Text('admin')),
      ),
    );
    await push(tester, const Scaffold(body: Text('edit')));
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byType(AppGlassButton), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('a replaced page leaves the depth, and the tabs, alone', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushReplacement(
          MaterialPageRoute<void>(builder: (_) => homeWithTabs()),
        );
    await tester.pumpAndSettle();

    expect(viewModel.pageDepth, 1);
    expect(find.byType(AppGlassPill), findsOneWidget);
  });

  testWidgets('runs down the right edge on a phone in landscape', (
    tester,
  ) async {
    useView(tester, const Size(844, 390));
    await tester.pumpWidget(app(homeWithTabs()));
    await tester.pumpAndSettle();

    final pill = tester.getRect(find.byType(AppGlassPill));
    expect(pill.width, kGlassSideThickness);
    expect(pill.height, greaterThan(pill.width));
    expect(pill.right, 844 - kControlsEdgeMargin);
    expect(pill.bottom, 390 - kControlsEdgeMargin);
  });

  testWidgets('keeps the side pill clear of a folded Duo camera', (
    tester,
  ) async {
    useView(tester, const Size(480, 340));
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(right: kSideControlsInsetWidth + 8),
          ),
          child: AppControlsHost(
            viewModel: viewModel,
            observer: observer,
            child: child!,
          ),
        ),
        home: homeWithTabs(),
      ),
    );
    await tester.pumpAndSettle();

    final pill = tester.getRect(find.byType(AppGlassPill));
    expect(340 - pill.bottom, greaterThanOrEqualTo(kCornerCameraClearance));
  });

  testWidgets('sits centred in a right inset wide enough to hold it', (
    tester,
  ) async {
    useView(tester, const Size(420, 300));
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(right: 80)),
          child: AppControlsHost(
            viewModel: viewModel,
            observer: observer,
            child: child!,
          ),
        ),
        home: homeWithTabs(),
      ),
    );
    await tester.pumpAndSettle();

    final pill = tester.getRect(find.byType(AppGlassPill));
    expect(pill.center.dx, 420 - 40, reason: 'middle of the 80pt strip');
  });

  testWidgets('tells the content how much room the controls take', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    EdgeInsets? seen;
    await tester.pumpWidget(
      app(
        AppNavTabsScope(
          viewModel: viewModel,
          tabs: AppNavTabs(
            destinations: _destinations,
            selectedIndex: 0,
            onSelected: (_) {},
          ),
          child: Builder(
            builder: (context) {
              seen = MediaQuery.paddingOf(context);
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      seen!.bottom,
      kControlsEdgeMargin + kGlassHorizontalThickness + kControlsEdgeMargin,
    );
  });

  testWidgets('asks nothing of the content where there are no controls', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    EdgeInsets? seen;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            seen = MediaQuery.paddingOf(context);
            return const Scaffold(body: Text('sign in'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, EdgeInsets.zero);
  });

  testWidgets('steps aside for the keyboard', (tester) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(homeWithTabs(), viewInsets: const EdgeInsets.only(bottom: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppGlassPill), findsNothing);
  });

  testWidgets('keeps a page\'s actions in reach above the keyboard', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(homeWithTabs(), viewInsets: const EdgeInsets.only(bottom: 300)),
    );
    await tester.pumpAndSettle();
    await push(
      tester,
      AppPageActions(
        viewModel: viewModel,
        actions: [
          AppGlassAction(icon: Icons.save, label: 'Save', onPressed: () {}),
        ],
        child: const Scaffold(body: Text('form')),
      ),
    );

    final group = tester.getRect(find.byType(AppGlassGroup));
    expect(group.bottom, lessThanOrEqualTo(844 - 300));
  });

  testWidgets('hides Back alone for the keyboard when a page has no actions', (
    tester,
  ) async {
    useView(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(homeWithTabs(), viewInsets: const EdgeInsets.only(bottom: 300)),
    );
    await tester.pumpAndSettle();
    await push(tester, const Scaffold(body: Text('filter')));

    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  for (final inset in [30.0, 51.0, 62.0, 80.0]) {
    testWidgets('the content clears the side pill with a ${inset}pt inset', (
      tester,
    ) async {
      useView(tester, const Size(844, 390));
      EdgeInsets? seen;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: EdgeInsets.only(right: inset)),
            child: AppControlsHost(
              viewModel: viewModel,
              observer: observer,
              child: child!,
            ),
          ),
          home: AppNavTabsScope(
            viewModel: viewModel,
            tabs: AppNavTabs(
              destinations: _destinations,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            child: Builder(
              builder: (context) {
                seen = MediaQuery.paddingOf(context);
                return const Scaffold(body: Text('home'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pill = tester.getRect(find.byType(AppGlassPill));
      expect(
        pill.left,
        greaterThanOrEqualTo(844 - seen!.right),
        reason: 'the content ends where the pill begins, or before',
      );
    });
  }
}
