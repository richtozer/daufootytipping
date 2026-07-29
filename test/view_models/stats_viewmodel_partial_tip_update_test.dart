import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundstats.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
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
  late DAURound round;
  late Game game;
  late Tipper alice;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    database = MockDatabaseReference();
    tippersViewModel = MockTippersViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    gamesViewModel = MockGamesViewModel();

    round = DAURound(
      dAUroundNumber: 1,
      firstGameKickOffUTC: DateTime.utc(2030, 1, 1),
      lastGameKickOffUTC: DateTime.utc(2030, 1, 2),
    );
    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: <DAURound>[round],
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
    game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-home', name: 'Home', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-away', name: 'Away', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2030, 1, 1, 12),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
    );
    round.games = <Game>[game];

    when(() => database.child(any())).thenReturn(database);

    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);

    when(() => tippersViewModel.selectedTipper).thenReturn(alice);
    when(() => tippersViewModel.isUserLinked).thenAnswer((_) async {});
    when(() => tippersViewModel.addListener(any())).thenReturn(null);
    when(() => tippersViewModel.removeListener(any())).thenReturn(null);
    when(() => tippersViewModel.findTipper('tipper-1')).thenAnswer((_) async {
      return alice;
    });

    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test('backend round stats map keys are converted to zero-based indexes', () async {
    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
      autoInitialize: false,
    );

    await viewModel.handleRoundPointsEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: <String, Object?>{
            '1': <String, Object?>{
              'tipper-1': RoundStats(
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
          },
        ),
      ),
    );

    expect(viewModel.allTipperRoundStats, contains(0));
    expect(viewModel.allTipperRoundStats, isNot(contains(1)));

    final roundStats = viewModel.getScoringRoundStats(round, alice);
    expect(roundStats.aflPoints, 2);
    expect(roundStats.nrlPoints, 6);

    viewModel.dispose();
  });

  test('backend round stats list keys are converted to zero-based indexes', () async {
    final roundTwo = DAURound(
      dAUroundNumber: 2,
      firstGameKickOffUTC: DateTime.utc(2030, 1, 8),
      lastGameKickOffUTC: DateTime.utc(2030, 1, 9),
    );
    comp.daurounds = <DAURound>[round, roundTwo];

    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: database,
      autoInitialize: false,
    );

    await viewModel.handleRoundPointsEventForTest(
      _databaseEvent(
        _snapshot(
          exists: true,
          value: <Object?>[
            null,
            <String, Object?>{
              'tipper-1': RoundStats(
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
            <String, Object?>{
              'tipper-1': RoundStats(
                roundNumber: 2,
                aflPoints: 4,
                aflMaxPoints: 6,
                aflMarginTips: 1,
                aflMarginUPS: 1,
                nrlPoints: 8,
                nrlMaxPoints: 10,
                nrlMarginTips: 2,
                nrlMarginUPS: 2,
                rank: 1,
                rankChange: 0,
                nrlTipsOutstanding: 0,
                aflTipsOutstanding: 0,
              ).toJson(),
            },
          ],
        ),
      ),
    );

    expect(viewModel.allTipperRoundStats, contains(0));
    expect(viewModel.allTipperRoundStats, contains(1));
    expect(viewModel.allTipperRoundStats, isNot(contains(2)));

    final roundOneStats = viewModel.getScoringRoundStats(round, alice);
    final roundTwoStats = viewModel.getScoringRoundStats(roundTwo, alice);
    expect(roundOneStats.roundNumber, 1);
    expect(roundOneStats.aflPoints, 2);
    expect(roundTwoStats.roundNumber, 2);
    expect(roundTwoStats.aflPoints, 4);

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
