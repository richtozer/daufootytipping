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
import 'package:intl/intl.dart';
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
  required DateTime lastLogin,
}) => Tipper(
  dbkey: key,
  authuid: 'auth-$key',
  email: '$key@example.com',
  logon: '$key@login.example.com',
  name: name,
  tipperRole: role,
  compsPaidFor: const [],
  acctLoggedOnUTC: lastLogin,
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
      _tipper('t2', 'Zara', lastLogin: DateTime.utc(2026, 3, 5)),
      _tipper(
        't1',
        'Maree',
        role: TipperRole.admin,
        lastLogin: DateTime.utc(2026, 3, 7),
      ),
      _tipper('t3', 'Alex', lastLogin: DateTime.utc(2026, 3, 1)),
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

  testWidgets('lists the tippers in a table, latest logon first', (
    tester,
  ) async {
    await openPage(tester);

    expect(find.byType(AppTable), findsOneWidget);
    expect(shown(tester), ['Maree', 'Zara', 'Alex']);
    expect(find.text('Showing 3 of 3 tippers'), findsOneWidget);
  });

  testWidgets('tapping the Name heading sorts by name', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();

    expect(shown(tester), ['Alex', 'Maree', 'Zara']);
  });

  testWidgets('marks admins under their name, with no Role column', (
    tester,
  ) async {
    await openPage(tester);

    expect(find.text('Role'), findsNothing);
    expect(find.text('admin'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('admin')).dy,
      greaterThan(tester.getTopLeft(find.text('Maree')).dy),
      reason: 'admin sits under the name',
    );
    expect(
      tester.getTopLeft(find.text('admin')).dx,
      tester.getTopLeft(find.text('Maree')).dx,
    );
    expect(
      tester.widget<Text>(find.text('admin')).style?.fontWeight,
      FontWeight.bold,
    );
    expect(
      tester.widget<Text>(find.text('Maree')).style?.fontWeight,
      isNot(FontWeight.bold),
    );
  });

  testWidgets('shows the last login date without the time', (tester) async {
    await openPage(tester);

    expect(
      find.text(
        DateFormat('dd MMM yy').format(DateTime.utc(2026, 3, 7).toLocal()),
      ),
      findsOneWidget,
    );
    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('the Paid heading turns on its side on a phone', (tester) async {
    await openPage(tester);

    expect(
      find.ancestor(of: find.text('Paid'), matching: find.byType(RotatedBox)),
      findsOneWidget,
    );
  });

  testWidgets('the filter narrows the rows', (tester) async {
    await openPage(tester);

    await tester.enterText(find.byType(TextField), 'zar');
    await tester.pumpAndSettle();

    expect(shown(tester), ['Zara']);
    expect(find.text('Showing 1 of 3 tippers'), findsOneWidget);
  });
}
