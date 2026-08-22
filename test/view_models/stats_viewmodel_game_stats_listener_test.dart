import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/scoring_gamestats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late MockDatabaseReference root;
  late MockDatabaseReference statsRoot;
  late MockDatabaseReference compRoot;
  late MockDatabaseReference gameStatsRoot;
  late MockDatabaseReference freeStatsRoot;
  late MockDatabaseReference paidStatsRoot;
  late MockDatabaseReference roundStatsRoot;
  late MockDatabaseReference liveScoresRoot;
  late MockTippersViewModel tippersViewModel;
  late StreamController<DatabaseEvent> freeStatsEvents;
  late StreamController<DatabaseEvent> paidStatsEvents;
  late VoidCallback tippersListener;
  late DAUComp comp;
  late Tipper viewer;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    root = MockDatabaseReference();
    statsRoot = MockDatabaseReference();
    compRoot = MockDatabaseReference();
    gameStatsRoot = MockDatabaseReference();
    freeStatsRoot = MockDatabaseReference();
    paidStatsRoot = MockDatabaseReference();
    roundStatsRoot = MockDatabaseReference();
    liveScoresRoot = MockDatabaseReference();
    tippersViewModel = MockTippersViewModel();
    freeStatsEvents = StreamController<DatabaseEvent>.broadcast();
    paidStatsEvents = StreamController<DatabaseEvent>.broadcast();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );
    viewer = _tipper(paidFor: null);

    when(
      () => root.child(
        '$statsPathRootLocal/${comp.dbkey}/${p.roundStatsBackendRoot}',
      ),
    ).thenReturn(roundStatsRoot);
    when(
      () => root.child(
        '$statsPathRootLocal/${comp.dbkey}/${p.liveScoresBackendRoot}',
      ),
    ).thenReturn(liveScoresRoot);
    when(() => root.child(statsPathRootLocal)).thenReturn(statsRoot);
    when(() => statsRoot.child(comp.dbkey!)).thenReturn(compRoot);
    when(
      () => compRoot.child(p.gameStatsBackendRoot),
    ).thenReturn(gameStatsRoot);
    when(() => gameStatsRoot.child('free')).thenReturn(freeStatsRoot);
    when(() => gameStatsRoot.child('paid')).thenReturn(paidStatsRoot);
    when(
      () => roundStatsRoot.onValue,
    ).thenAnswer((_) => const Stream<DatabaseEvent>.empty());
    when(
      () => liveScoresRoot.onValue,
    ).thenAnswer((_) => const Stream<DatabaseEvent>.empty());
    when(
      () => freeStatsRoot.onValue,
    ).thenAnswer((_) => freeStatsEvents.stream);
    when(
      () => paidStatsRoot.onValue,
    ).thenAnswer((_) => paidStatsEvents.stream);

    when(() => tippersViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.selectedTipper).thenAnswer((_) => viewer);
    when(() => tippersViewModel.tippers).thenAnswer((_) => <Tipper>[viewer]);
    when(() => tippersViewModel.addListener(any())).thenAnswer((invocation) {
      tippersListener = invocation.positionalArguments.single as VoidCallback;
    });
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
  });

  tearDown(() async {
    await freeStatsEvents.close();
    await paidStatsEvents.close();
    await di.reset();
  });

  test('switches the game stats listener when the viewer cohort changes', () async {
    final viewModel = StatsViewModel(
      comp,
      null,
      database: root,
      refreshProtectedResourceAccess: () async {},
    );
    await _settleAsyncWork();

    expect(freeStatsEvents.hasListener, isTrue);
    expect(paidStatsEvents.hasListener, isFalse);
    viewModel.gamesStatsEntry['nrl-01-001'] = GameStatsEntry(
      percentageTippedHomeMargin: 0,
      percentageTippedHome: 1,
      percentageTippedDraw: 0,
      percentageTippedAway: 0,
      percentageTippedAwayMargin: 0,
      averagePoints: 1,
      averagePointsTipCount: 1,
    );

    viewer = _tipper(paidFor: comp);
    tippersListener();
    await _settleAsyncWork();

    expect(freeStatsEvents.hasListener, isFalse);
    expect(paidStatsEvents.hasListener, isTrue);
    expect(viewModel.gamesStatsEntry, isEmpty);

    viewModel.dispose();
  });

  test('does not replace complete stats with a partial listener entry', () async {
    final viewModel = StatsViewModel(
      comp,
      null,
      database: root,
      autoInitialize: false,
      refreshProtectedResourceAccess: () async {},
    );
    final completeEntry = GameStatsEntry(
      percentageTippedHomeMargin: 0,
      percentageTippedHome: 0.625,
      percentageTippedDraw: 0,
      percentageTippedAway: 0.375,
      percentageTippedAwayMargin: 0,
      averagePoints: 1.5,
      averagePointsTipCount: 57,
    );
    viewModel.gamesStatsEntry['nrl-01-001'] = completeEntry;
    final snapshot = MockDataSnapshot();
    final event = MockDatabaseEvent();
    when(() => snapshot.exists).thenReturn(true);
    when(() => snapshot.value).thenReturn(<String, Object?>{
      'nrl-01-001': <String, Object?>{'avgScore': 0.0},
    });
    when(() => event.snapshot).thenReturn(snapshot);

    await viewModel.handleGameStatsEventForTest(event);

    expect(viewModel.gamesStatsEntry['nrl-01-001'], same(completeEntry));

    viewModel.dispose();
  });

  test('reconnects after an iOS protected-resource listener error', () async {
    var protectedResourceRefreshes = 0;
    final replacementPaidEvents = StreamController<DatabaseEvent>.broadcast();
    addTearDown(replacementPaidEvents.close);
    var paidListenerCount = 0;
    when(() => paidStatsRoot.onValue).thenAnswer((_) {
      paidListenerCount += 1;
      return paidListenerCount == 1
          ? paidStatsEvents.stream
          : replacementPaidEvents.stream;
    });
    viewer = _tipper(paidFor: comp);

    final viewModel = StatsViewModel(
      comp,
      null,
      database: root,
      gameStatsListenerRetryDelays: const [Duration.zero],
      refreshProtectedResourceAccess: () async {
        protectedResourceRefreshes += 1;
      },
    );
    await _settleAsyncWork();

    paidStatsEvents.addError(
      FirebaseException(
        plugin: 'firebase_database',
        code: 'permission-denied',
        message: 'App Check token rejected.',
      ),
      StackTrace.current,
    );
    await _settleAsyncWork();

    expect(protectedResourceRefreshes, 1);
    expect(paidListenerCount, 2);
    expect(paidStatsEvents.hasListener, isFalse);
    expect(replacementPaidEvents.hasListener, isTrue);

    replacementPaidEvents.addError(
      FirebaseException(
        plugin: 'firebase_database',
        code: 'permission-denied',
        message: 'App Check token still unavailable.',
      ),
      StackTrace.current,
    );
    await _settleAsyncWork();

    expect(protectedResourceRefreshes, 2);
    expect(paidListenerCount, 3);
    expect(replacementPaidEvents.hasListener, isTrue);

    replacementPaidEvents.add(
      _gameStatsEvent(
        gameKey: 'nrl-01-001',
        percentageTippedHome: 0.625,
      ),
    );
    await _settleAsyncWork();

    expect(
      viewModel.gamesStatsEntry['nrl-01-001']?.percentageTippedHome,
      0.625,
    );

    viewModel.dispose();
  });
}

Tipper _tipper({required DAUComp? paidFor}) {
  return Tipper(
    dbkey: 'tipper-1',
    authuid: 'auth-1',
    email: 'tipper@example.com',
    logon: 'tipper@example.com',
    name: 'Tipper One',
    tipperRole: TipperRole.tipper,
    compsPaidFor: paidFor == null ? <DAUComp>[] : <DAUComp>[paidFor],
  );
}

DatabaseEvent _gameStatsEvent({
  required String gameKey,
  required double percentageTippedHome,
}) {
  final snapshot = MockDataSnapshot();
  final event = MockDatabaseEvent();
  when(() => snapshot.exists).thenReturn(true);
  when(() => snapshot.value).thenReturn(<String, Object?>{
    gameKey: <String, Object?>{
      'pctTipA': 0.0,
      'pctTipB': percentageTippedHome,
      'pctTipC': 0.0,
      'pctTipD': 1 - percentageTippedHome,
      'pctTipE': 0.0,
    },
  });
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

Future<void> _settleAsyncWork() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
