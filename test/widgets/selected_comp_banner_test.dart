import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/widgets/selected_comp_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;

  setUp(() {
    dauCompsViewModel = MockDAUCompsViewModel();
    when(() => dauCompsViewModel.addListener(any())).thenAnswer((_) {});
    when(() => dauCompsViewModel.removeListener(any())).thenAnswer((_) {});
  });

  testWidgets('shows the selected comp year when viewing a past competition', (
    tester,
  ) async {
    when(
      () => dauCompsViewModel.selectedDAUComp,
    ).thenReturn(_buildComp('DAU Footy Tipping 2024'));
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(false);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SelectedCompBanner(
          dauCompsViewModel: dauCompsViewModel,
          child: const Scaffold(body: Text('Stats')),
        ),
      ),
    );

    final Banner banner = tester.widget<Banner>(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == '2024',
      ),
    );
    expect(banner.message, '2024');
    expect(find.text('Stats'), findsOneWidget);
  });

  testWidgets('does not show a banner for the active competition', (
    tester,
  ) async {
    when(
      () => dauCompsViewModel.selectedDAUComp,
    ).thenReturn(_buildComp('DAU Footy Tipping 2026'));
    when(() => dauCompsViewModel.isSelectedCompActiveComp()).thenReturn(true);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SelectedCompBanner(
          dauCompsViewModel: dauCompsViewModel,
          child: const Scaffold(body: Text('Stats')),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Banner && widget.message == '2026',
      ),
      findsNothing,
    );
    expect(find.text('Stats'), findsOneWidget);
  });
}

DAUComp _buildComp(String name) {
  return DAUComp(
    dbkey: name,
    name: name,
    aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
    nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
    daurounds: const [],
  );
}
