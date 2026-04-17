import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockTippersViewModel tippersViewModel;
  late MockDAUCompsViewModel dauCompsViewModel;
  late MockDatabaseReference database;
  late DAUComp comp;
  late Tipper alice;
  late Tipper bob;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    tippersViewModel = MockTippersViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    database = MockDatabaseReference();

    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 4, 1),
          lastGameKickOffUTC: DateTime.utc(2026, 4, 2),
        ),
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 4, 8),
          lastGameKickOffUTC: DateTime.utc(2026, 4, 9),
        ),
      ],
    );

    alice = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'alice@example.com',
      logon: 'alice@example.com',
      name: 'Alice',
      tipperRole: TipperRole.tipper,
      compsPaidFor: <DAUComp>[comp],
    );
    bob = Tipper(
      dbkey: 'tipper-2',
      authuid: 'auth-2',
      email: 'bob@example.com',
      logon: 'bob@example.com',
      name: 'Bob',
      tipperRole: TipperRole.tipper,
      compsPaidFor: <DAUComp>[comp],
    );

    when(() => tippersViewModel.selectedTipper).thenReturn(alice);
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.addListener(any())).thenReturn(null);
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.findTipper(any())).thenAnswer((invocation) async {
      switch (invocation.positionalArguments.single as String) {
        case 'tipper-1':
          return alice;
        case 'tipper-2':
          return bob;
        default:
          return null;
      }
    });

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test('builds a scoring change report from before and after snapshots', () async {
    final viewModel = StatsViewModel(
      comp,
      null,
      database: database,
      autoInitialize: false,
    );

    await viewModel.handleRoundScoresEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: _roundScoresPayload(
            roundOneAliceTotal: 5,
            roundOneBobTotal: 3,
            roundTwoAliceTotal: 6,
            roundTwoBobTotal: 10,
          ),
        ),
      ),
    );
    final beforeSnapshot = await viewModel.captureScoringSnapshotForTest();

    await viewModel.handleRoundScoresEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: _roundScoresPayload(
            roundOneAliceTotal: 8,
            roundOneBobTotal: 3,
            roundTwoAliceTotal: 8,
            roundTwoBobTotal: 6,
          ),
        ),
      ),
    );
    final afterSnapshot = await viewModel.captureScoringSnapshotForTest();

    final report = viewModel.buildScoringUpdateReportForTest(
      beforeSnapshot,
      afterSnapshot,
      'Completed updates for 2 tippers and 2 rounds.',
    );

    expect(report.resultMessage, 'Completed updates for 2 tippers and 2 rounds.');
    expect(report.hasChanges, isTrue);
    expect(report.changedTippersCount, 2);
    expect(report.changedLeaderboardEntriesCount, 2);
    expect(report.changedRoundEntriesCount, 3);
    expect(report.rankMoveCount, 2);

    final aliceLeaderboard = report.leaderboardChanges.firstWhere(
      (change) => change.tipperName == 'Alice',
    );
    expect(aliceLeaderboard.beforeRank, 2);
    expect(aliceLeaderboard.afterRank, 1);
    expect(aliceLeaderboard.beforeTotal, 11);
    expect(aliceLeaderboard.afterTotal, 16);
    expect(aliceLeaderboard.totalDelta, 5);

    final bobRoundTwo = report.roundChanges.firstWhere(
      (change) => change.tipperName == 'Bob' && change.roundNumber == 2,
    );
    expect(bobRoundTwo.beforeTotal, 10);
    expect(bobRoundTwo.afterTotal, 6);
    expect(bobRoundTwo.totalDelta, -4);
    expect(bobRoundTwo.beforeRank, 1);
    expect(bobRoundTwo.afterRank, 2);

    viewModel.dispose();
  });
}

MockDatabaseEvent _databaseEvent(DataSnapshot snapshot) {
  final event = MockDatabaseEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _snapshot({
  required bool exists,
  required Object? value,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}

List<Object?> _roundScoresPayload({
  required int roundOneAliceTotal,
  required int roundOneBobTotal,
  required int roundTwoAliceTotal,
  required int roundTwoBobTotal,
}) {
  return <Object?>[
    <String, Map<String, int>>{
      'tipper-1': _roundStatsJson(roundNumber: 1, total: roundOneAliceTotal),
      'tipper-2': _roundStatsJson(roundNumber: 1, total: roundOneBobTotal),
    },
    <String, Map<String, int>>{
      'tipper-1': _roundStatsJson(roundNumber: 2, total: roundTwoAliceTotal),
      'tipper-2': _roundStatsJson(roundNumber: 2, total: roundTwoBobTotal),
    },
  ];
}

Map<String, int> _roundStatsJson({
  required int roundNumber,
  required int total,
}) {
  return RoundStats(
    roundNumber: roundNumber,
    aflScore: 0,
    aflMaxScore: 1,
    aflMarginTips: 0,
    aflMarginUPS: 0,
    nrlScore: total,
    nrlMaxScore: total + 1,
    nrlMarginTips: 0,
    nrlMarginUPS: 0,
    rank: 0,
    rankChange: 0,
    nrlTipsOutstanding: 0,
    aflTipsOutstanding: 0,
  ).toJson();
}
