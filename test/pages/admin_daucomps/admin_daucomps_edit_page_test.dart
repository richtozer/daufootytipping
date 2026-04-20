import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockGlobalDauCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockGlobalDauCompsViewModel globalDauCompsViewModel;
  late DAUComp activeComp;
  late DAUComp viewedComp;

  setUp(() async {
    await di.reset();

    globalDauCompsViewModel = MockGlobalDauCompsViewModel();
    activeComp = _buildComp('active-comp', 'DAU Footy Tipping 2026');
    viewedComp = _buildComp('viewed-comp', 'DAU Footy Tipping 2024');

    when(
      () => globalDauCompsViewModel.initDAUCompDbKey,
    ).thenReturn(activeComp.dbkey);
    when(() => globalDauCompsViewModel.activeDAUComp).thenReturn(activeComp);
    when(
      () => globalDauCompsViewModel.changeDisplayedDAUComp(activeComp, false),
    ).thenAnswer((_) async {});

    di.registerSingleton<DAUCompsViewModel>(globalDauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets(
    'leaving admin edit does not reset the global selected competition',
    (tester) async {
      final adminPageViewModel = DAUCompsViewModel(
        viewedComp.dbkey,
        true,
        skipInit: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DAUCompsEditPage(
                        viewedComp,
                        adminDauCompsViewModel: adminPageViewModel,
                      ),
                    ),
                  );
                },
                child: const Text('Open admin edit'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open admin edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit DAU Comp'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Open admin edit'), findsOneWidget);
      verifyNever(
        () => globalDauCompsViewModel.changeDisplayedDAUComp(activeComp, false),
      );
    },
  );
}

DAUComp _buildComp(String dbKey, String name) {
  return DAUComp(
    dbkey: dbKey,
    name: name,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: const [],
  );
}
