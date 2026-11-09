import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/pages/user_home/user_home_stats_percent_tipped.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

import '../../mocks/mock_daucomps_viewmodel.dart';

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;

  setUp(() async {
    await di.reset();
    dauCompsViewModel = MockDAUCompsViewModel();
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(null);
    when(() => dauCompsViewModel.activeDAUComp).thenReturn(null);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  testWidgets('points tippers to the support site when no comp is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatPercentTipped())),
    );

    expect(
      find.text('Nothing to see here.\nContact support: ${p.supportUrl}.'),
      findsOneWidget,
    );
  });
}
