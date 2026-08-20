import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

void main() {
  late MockDatabaseReference database;
  late MockTippersViewModel tippersViewModel;
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockGamesViewModel gamesViewModel;
  late DAUComp comp;
  late Tipper viewer;
  late Tipper originalTipper;
  late VoidCallback tippersListener;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    database = MockDatabaseReference();
    tippersViewModel = MockTippersViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    gamesViewModel = MockGamesViewModel();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2030, 1, 1),
          lastGameKickOffUTC: DateTime.utc(2030, 1, 2),
        ),
      ],
    );
    viewer = _tipper('viewer', paidFor: comp);
    originalTipper = _tipper('new-tipper');

    when(() => database.child(any())).thenReturn(database);
    when(() => database.onValue).thenAnswer((_) => const Stream.empty());
    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.initialLoadComplete).thenAnswer((_) async {});
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.selectedTipper).thenReturn(viewer);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[
      viewer,
      originalTipper,
    ]);
    when(() => tippersViewModel.findTipper('new-tipper')).thenAnswer(
      (_) async => originalTipper,
    );
    when(() => tippersViewModel.addListener(any())).thenAnswer((invocation) {
      tippersListener = invocation.positionalArguments.single as VoidCallback;
    });
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test('moves existing stats into paid cohort when tipper becomes paid', () async {
    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.handleRoundPointsEventForTest(_roundPointsEvent());
    expect(viewModel.compLeaderboard, isEmpty);

    final paidTipper = _tipper('new-tipper', paidFor: comp);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[
      viewer,
      paidTipper,
    ]);

    tippersListener();
    await Future<void>.delayed(Duration.zero);

    expect(
      viewModel.compLeaderboard.map((entry) => entry.tipper),
      contains(same(paidTipper)),
    );

    viewModel.dispose();
  });

  test('moves existing stats into free cohort when tipper becomes free', () async {
    viewer = _tipper('viewer');
    originalTipper = _tipper('new-tipper', paidFor: comp);
    when(() => tippersViewModel.selectedTipper).thenReturn(viewer);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[
      viewer,
      originalTipper,
    ]);
    when(() => tippersViewModel.findTipper('new-tipper')).thenAnswer(
      (_) async => originalTipper,
    );

    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.handleRoundPointsEventForTest(_roundPointsEvent());
    expect(viewModel.compLeaderboard, isEmpty);

    final freeTipper = _tipper('new-tipper');
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[
      viewer,
      freeTipper,
    ]);

    tippersListener();
    await Future<void>.delayed(Duration.zero);

    expect(
      viewModel.compLeaderboard.map((entry) => entry.tipper),
      contains(same(freeTipper)),
    );

    viewModel.dispose();
  });

  test('keeps stats that arrive before a new tipper snapshot', () async {
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[viewer]);
    when(() => tippersViewModel.findTipper('new-tipper')).thenAnswer(
      (_) async => null,
    );

    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.handleRoundPointsEventForTest(_roundPointsEvent());
    expect(viewModel.compLeaderboard, isEmpty);

    final paidTipper = _tipper('new-tipper', paidFor: comp);
    when(() => tippersViewModel.tippers).thenReturn(<Tipper>[
      viewer,
      paidTipper,
    ]);

    tippersListener();
    await Future<void>.delayed(Duration.zero);

    expect(
      viewModel.compLeaderboard.map((entry) => entry.tipper),
      contains(same(paidTipper)),
    );

    viewModel.dispose();
  });
}

DatabaseEvent _roundPointsEvent() {
  final snapshot = MockDataSnapshot();
  final event = MockDatabaseEvent();
  when(() => snapshot.exists).thenReturn(true);
  when(() => snapshot.value).thenReturn(<String, Object?>{
    '1': <String, Object?>{
      'new-tipper': RoundStats(
        roundNumber: 1,
        aflPoints: 2,
        aflMaxPoints: 4,
        aflMarginTips: 1,
        aflMarginUPS: 0,
        nrlPoints: 6,
        nrlMaxPoints: 8,
        nrlMarginTips: 2,
        nrlMarginUPS: 1,
        rank: 1,
        rankChange: 0,
        nrlTipsOutstanding: 0,
        aflTipsOutstanding: 0,
      ).toJson(),
    },
  });
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

Tipper _tipper(String key, {DAUComp? paidFor}) {
  return Tipper(
    dbkey: key,
    authuid: 'auth-$key',
    email: '$key@example.com',
    logon: '$key@example.com',
    name: key,
    tipperRole: TipperRole.tipper,
    compsPaidFor: paidFor == null ? <DAUComp>[] : <DAUComp>[paidFor],
  );
}
