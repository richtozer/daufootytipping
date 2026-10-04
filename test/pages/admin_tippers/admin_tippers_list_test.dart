import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/view_models/app_controls_viewmodel.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/search_query_provider.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_table/app_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';

import '../../support/app_controls_test_app.dart';
import '../../support/load_tips_fonts.dart';

class _MockTippersViewModel extends Mock implements TippersViewModel {}

class _MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

Tipper _tipper(
  String key,
  String name, {
  TipperRole role = TipperRole.tipper,
}) => Tipper(
  dbkey: key,
  authuid: 'auth-$key',
  email: '$key@example.com',
  logon: '$key@login.example.com',
  name: name,
  tipperRole: role,
  compsPaidFor: const [],
  acctLoggedOnUTC: DateTime.utc(2026, 3, 5),
);

void main() {
  setUpAll(loadTipsFonts);

  late _MockTippersViewModel tippersViewModel;
  late AppControlsViewModel appControls;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;
    appControls = registerAppControlsViewModel();
    tippersViewModel = _MockTippersViewModel();
    final dauCompsViewModel = _MockDAUCompsViewModel();
    final tippers = [
      _tipper('t2', 'Zara'),
      _tipper('t1', 'Maree', role: TipperRole.admin),
      _tipper('t3', 'Alex'),
    ];
    when(() => tippersViewModel.addListener(any())).thenReturn(null);
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.tippers).thenReturn(tippers);
    when(() => tippersViewModel.inGodMode).thenReturn(false);
    when(() => tippersViewModel.selectedTipper).thenReturn(tippers.first);
    when(() => dauCompsViewModel.activeDAUComp).thenReturn(null);
    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });
  tearDown(() async {
    await di.reset();
    appControls.dispose();
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SearchQueryProvider(),
        child: appWithControls(appControls, home: const SizedBox.shrink()),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(builder: (_) => const TippersAdminPage()),
        );
    await tester.pumpAndSettle();
  }

  List<String> shown(WidgetTester tester) =>
      [
        for (final name in ['Alex', 'Maree', 'Zara'])
          if (find.text(name).evaluate().isNotEmpty) name,
      ]..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );

  testWidgets('lists the tippers in a table sorted by name', (tester) async {
    await openPage(tester);

    expect(find.byType(AppTable), findsOneWidget);
    expect(shown(tester), ['Alex', 'Maree', 'Zara']);
    expect(find.text('Showing 3 of 3 tippers'), findsOneWidget);
  });

  testWidgets('tapping the Role heading sorts by role', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Role'));
    await tester.pumpAndSettle();

    // admin sorts before tipper, then by name within a role.
    expect(shown(tester), ['Maree', 'Alex', 'Zara']);
  });

  testWidgets('the filter narrows the rows', (tester) async {
    await openPage(tester);

    await tester.enterText(find.byType(TextField), 'zar');
    await tester.pumpAndSettle();

    expect(shown(tester), ['Zara']);
    expect(find.text('Showing 1 of 3 tippers'), findsOneWidget);
  });
}
