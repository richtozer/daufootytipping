import 'dart:async';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_edit_buttons.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mocktail/mocktail.dart';

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockStatsViewModel extends Mock implements StatsViewModel {}
class MockDatabaseReference extends Mock implements DatabaseReference {}
class MockDatabaseEvent extends Mock implements DatabaseEvent {}
class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockStatsViewModel statsViewModel;
  late DAUComp comp;

  setUp(() {
    dauCompsViewModel = MockDAUCompsViewModel();
    statsViewModel = MockStatsViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    when(() => dauCompsViewModel.statsViewModel).thenReturn(statsViewModel);
    when(() => dauCompsViewModel.isDownloading).thenReturn(false);
    when(
      () => dauCompsViewModel.lastFixtureDownloadRanViaCloudFunction,
    ).thenReturn(false);
    when(
      () => dauCompsViewModel.getNetworkFixtureData(comp),
    ).thenAnswer((_) async => 'Fixture download complete.');
    when(
      () => dauCompsViewModel.rescoreWithBackend(comp),
    ).thenAnswer((_) async => 'Backend rescore complete.');
    when(() => statsViewModel.isUpdateScoringRunning).thenReturn(false);
    when(() => statsViewModel.scoringProgressMessage).thenReturn(null);
    when(() => statsViewModel.scoringProgressValue).thenReturn(null);
    when(() => statsViewModel.addListener(any())).thenReturn(null);
    when(() => statsViewModel.removeListener(any())).thenReturn(null);
  });

  testWidgets('allows fixture download through the backend', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditFixtureButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    verify(() => dauCompsViewModel.getNetworkFixtureData(comp)).called(1);
    expect(find.text('Fixture download complete.'), findsOneWidget);
  });

  testWidgets('shows manual repair steps with fixture download off by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();

    expect(find.text('Run admin updates'), findsOneWidget);
    expect(
      find.text(
        'Fixture downloads and scoring updates are normally handled automatically. Use these manual repair steps only when you see fixture, scoring, or average point issues.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Download fixtures'),
      ).value,
      isFalse,
    );
    expect(
      tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Recalculate scoring'),
      ).value,
      isTrue,
    );
    expect(find.textContaining('Fixture status'), findsNothing);
    expect(find.text('Nothing to do'), findsNothing);
    expect(find.text('Rebuild game averages'), findsNothing);
  });

  testWidgets('runs manual scoring through the backend', (
    tester,
  ) async {
    final disableBackStates = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: disableBackStates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(disableBackStates, contains(true));
    expect(find.text('Backend rescore complete.'), findsOneWidget);
    verifyNever(() => dauCompsViewModel.getNetworkFixtureData(comp));
    verify(() => dauCompsViewModel.rescoreWithBackend(comp)).called(1);

    expect(disableBackStates.last, false);
  });

  testWidgets('runs backend scoring after local fixture download', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Download fixtures'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    verify(() => dauCompsViewModel.getNetworkFixtureData(comp)).called(1);
    verify(() => dauCompsViewModel.rescoreWithBackend(comp)).called(1);
  });

  testWidgets('skips UI scoring after backend fixture download', (
    tester,
  ) async {
    when(
      () => dauCompsViewModel.lastFixtureDownloadRanViaCloudFunction,
    ).thenReturn(true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Download fixtures'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    verify(() => dauCompsViewModel.getNetworkFixtureData(comp)).called(1);
    verifyNever(() => dauCompsViewModel.rescoreWithBackend(comp));
    expect(find.text('Fixture download complete.'), findsOneWidget);
  });

  testWidgets('shows progress dialog while manual admin update is running', (
    tester,
  ) async {
    final reportCompleter = Completer<String>();
    when(() => statsViewModel.scoringProgressMessage).thenReturn(
      'Rebuilding game averages 3/10...',
    );
    when(() => statsViewModel.scoringProgressValue).thenReturn(0.3);
    when(() => dauCompsViewModel.rescoreWithBackend(comp))
        .thenAnswer((_) => reportCompleter.future);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.text('Running updates'), findsOneWidget);
    expect(find.text('Rebuilding game averages 3/10...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    reportCompleter.complete('Backend rescore complete.');
    await tester.pumpAndSettle();

    expect(find.text('Backend rescore complete.'), findsOneWidget);
  });

  testWidgets('shows configuration detail for a rescore StateError', (
    tester,
  ) async {
    when(() => dauCompsViewModel.rescoreWithBackend(comp)).thenThrow(
      StateError('Backend scoring URL is not configured.'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Backend scoring URL is not configured.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the backend completion message once', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminDaucompsEditScoringButton(
            dauCompsViewModel: dauCompsViewModel,
            daucomp: comp,
            setStateCallback: (_) {},
            onDisableBack: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    expect(find.text('Backend rescore complete.'), findsOneWidget);
  });

  testWidgets('shows applied fixture status from the new schema', (tester) async {
    final mockStatusRef = MockDatabaseReference();
    final mockStatusEvent = MockDatabaseEvent();
    final mockStatusSnapshot = MockDataSnapshot();
    final controller = StreamController<DatabaseEvent>();
    final now = DateTime.now().toUtc();

    when(() => mockStatusRef.onValue).thenAnswer((_) => controller.stream);
    when(() => mockStatusEvent.snapshot).thenReturn(mockStatusSnapshot);
    when(() => mockStatusSnapshot.value).thenReturn({
      'state': 'applied',
      'lastCheckedAt': now.subtract(const Duration(hours: 3)).toIso8601String(),
      'lastAppliedAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      'message': 'Fixture data loaded.',
    });

    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FixtureDownloadStatusBanner(
            comp: comp,
            statusReference: mockStatusRef,
          ),
        ),
      ),
    );

    controller.add(mockStatusEvent);
    await tester.pumpAndSettle();

    expect(find.text('Fixture changes applied'), findsOneWidget);
    expect(find.textContaining('Fixture changes last applied 1 day ago.'), findsOneWidget);
  });

  testWidgets('shows nothing_to_do status from the new schema', (tester) async {
    final mockStatusRef = MockDatabaseReference();
    final mockStatusEvent = MockDatabaseEvent();
    final mockStatusSnapshot = MockDataSnapshot();
    final controller = StreamController<DatabaseEvent>();
    final now = DateTime.now().toUtc();

    when(() => mockStatusRef.onValue).thenAnswer((_) => controller.stream);
    when(() => mockStatusEvent.snapshot).thenReturn(mockStatusSnapshot);
    when(() => mockStatusSnapshot.value).thenReturn({
      'state': 'nothing_to_do',
      'lastCheckedAt': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'message': 'No started games without fixture results were found.',
    });

    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FixtureDownloadStatusBanner(
            comp: comp,
            statusReference: mockStatusRef,
          ),
        ),
      ),
    );

    controller.add(mockStatusEvent);
    await tester.pumpAndSettle();

    expect(find.text('Nothing to do'), findsOneWidget);
    expect(
      find.textContaining('Last checked 2 hours ago.'),
      findsOneWidget,
    );
  });
}
