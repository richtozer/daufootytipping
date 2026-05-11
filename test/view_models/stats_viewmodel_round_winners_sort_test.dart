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

  test(
    'reapplies the active round winners sort after an external scoring refresh',
    () async {
      final viewModel = StatsViewModel(
        comp,
        null,
        database: database,
        autoInitialize: false,
      );

      await viewModel.handleRoundPointsEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: _roundPointsPayload(
              roundOneWinnerTotal: 5,
              roundTwoWinnerTotal: 10,
            ),
          ),
        ),
      );
      await _settleBackgroundStats();

      viewModel.sortRoundWinnersByTotal(true);
      expect(
        viewModel.roundWinners.values
            .map((winners) => winners.first.roundNumber)
            .toList(),
        <int>[1, 2],
      );

      await viewModel.handleRoundPointsEventForTest(
        _databaseEvent(
          _snapshot(
            exists: true,
            value: _roundPointsPayload(
              roundOneWinnerTotal: 15,
              roundTwoWinnerTotal: 10,
            ),
          ),
        ),
      );
      await _settleBackgroundStats();

      expect(
        viewModel.roundWinners.values
            .map((winners) => winners.first.roundNumber)
            .toList(),
        <int>[2, 1],
      );

      viewModel.dispose();
    },
  );
}

Future<void> _settleBackgroundStats() async {
  await Future<void>.delayed(Duration.zero);
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

List<Object?> _roundPointsPayload({
  required int roundOneWinnerTotal,
  required int roundTwoWinnerTotal,
}) {
  return <Object?>[
    <String, Map<String, int>>{
      'tipper-1': _roundStatsJson(roundNumber: 1, total: roundOneWinnerTotal),
      'tipper-2': _roundStatsJson(roundNumber: 1, total: 3),
    },
    <String, Map<String, int>>{
      'tipper-1': _roundStatsJson(roundNumber: 2, total: 6),
      'tipper-2': _roundStatsJson(roundNumber: 2, total: roundTwoWinnerTotal),
    },
  ];
}

Map<String, int> _roundStatsJson({
  required int roundNumber,
  required int total,
}) {
  return RoundStats(
    roundNumber: roundNumber,
    aflPoints: 0,
    aflMaxPoints: 1,
    aflMarginTips: 0,
    aflMarginUPS: 0,
    nrlPoints: total,
    nrlMaxPoints: total + 1,
    nrlMarginTips: 0,
    nrlMarginUPS: 0,
    rank: 0,
    rankChange: 0,
    nrlTipsOutstanding: 0,
    aflTipsOutstanding: 0,
  ).toJson();
}
