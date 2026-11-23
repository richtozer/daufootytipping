import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
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

  Finder banner(String message) => find.byWidgetPredicate(
    (widget) => widget is Banner && widget.message == message,
  );
  const window = Rect.fromLTWH(0, 0, 1200, 800);

  testWidgets('a past comp\'s year sits in the window\'s corner, not the '
      'narrow page\'s', (tester) async {
    await openPageInWideWindow(tester);

    expect(tester.getRect(banner('2025')), window);
    expect(
      tester.widget<Banner>(banner('2025')).location,
      BannerLocation.bottomStart,
    );
  });

  testWidgets('the banners sit just clear of the nav controls, so the tab '
      'pill or Back never covers them', (tester) async {
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(
      tester,
      controlsRoom: const EdgeInsets.only(bottom: 96),
    );

    // Both ribbons share the area above the controls' strip.
    const clearOfControls = Rect.fromLTWH(0, 0, 1200, 704);
    expect(tester.getRect(banner('2025')), clearOfControls);
    expect(tester.getRect(banner('Daisy')), clearOfControls);
  });

  testWidgets('the banner is part of the page, so a dialog or sheet opened '
      'over it covers it', (tester) async {
    await openPageInWideWindow(tester);

    // Inside the page's route, rather than around the navigator that also
    // holds the dialogs and sheets.
    expect(
      find.ancestor(of: banner('2025'), matching: find.byType(Navigator)),
      findsOneWidget,
    );
  });

  testWidgets('the active comp has no year banner', (tester) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);

    await openPageInWideWindow(tester);

    expect(find.byType(Banner), findsNothing);
  });

  testWidgets('god mode is one red banner with the tipper\'s name, in the '
      'window\'s bottom-right corner', (tester) async {
    when(() => comps.isSelectedCompActiveComp()).thenReturn(true);
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(tester);

    expect(find.byType(Banner), findsOneWidget);
    final godMode = tester.widget<Banner>(banner('Daisy'));
    expect(godMode.location, BannerLocation.bottomEnd);
    expect(godMode.color, Colors.red);
    expect(tester.getRect(banner('Daisy')), window);
  });

  testWidgets('god mode on a past comp shows both: the year bottom-left and '
      'the tipper bottom-right', (tester) async {
    when(() => tippers.inGodMode).thenReturn(true);

    await openPageInWideWindow(tester);

    expect(
      tester.widget<Banner>(banner('2025')).location,
      BannerLocation.bottomStart,
    );
    expect(
      tester.widget<Banner>(banner('Daisy')).location,
      BannerLocation.bottomEnd,
    );
  });

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

    expect(banner('2025'), findsOneWidget);
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
    expect(find.byType(Banner), findsNothing);
  });
}
