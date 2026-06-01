import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/games_viewmodel.dart';
import 'package:daufootytipping/view_models/stats_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:watch_it/watch_it.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockGamesViewModel extends Mock implements GamesViewModel {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

class MockDAUCompsViewModel extends Mock implements DAUCompsViewModel {}

void main() {
  late MockDatabaseReference rootDb;
  late MockDatabaseReference connectedRef;
  late MockDatabaseReference statsRef;
  late MockDatabaseReference compStatsRef;
  late MockDatabaseReference probeRef;
  late MockDatabaseReference tipsRef;
  late MockGamesViewModel gamesViewModel;
  late MockTippersViewModel tippersViewModel;
  late MockDAUCompsViewModel dauCompsViewModel;
  late DAUComp comp;

  setUp(() async {
    await di.reset();
    di.allowReassignment = true;

    rootDb = MockDatabaseReference();
    connectedRef = MockDatabaseReference();
    statsRef = MockDatabaseReference();
    compStatsRef = MockDatabaseReference();
    probeRef = MockDatabaseReference();
    tipsRef = MockDatabaseReference();
    gamesViewModel = MockGamesViewModel();
    tippersViewModel = MockTippersViewModel();
    dauCompsViewModel = MockDAUCompsViewModel();
    comp = DAUComp(
      dbkey: 'comp-1',
      name: 'Test Comp',
      aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
      nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
      daurounds: const [],
    );

    when(() => rootDb.child('/Stats')).thenReturn(statsRef);
    when(() => statsRef.child('comp-1')).thenReturn(compStatsRef);
    when(
      () => compStatsRef.child(adminScoringFreshnessProbePath),
    ).thenReturn(probeRef);
    when(() => rootDb.child('/AllTips/comp-1')).thenReturn(tipsRef);

    when(() => probeRef.set(any())).thenAnswer((_) async {});
    when(() => tipsRef.get()).thenAnswer(
      (_) async => _snapshot(exists: false, value: null),
    );
    when(() => gamesViewModel.addListener(any())).thenReturn(null);
    when(() => gamesViewModel.removeListener(any())).thenReturn(null);
    when(() => gamesViewModel.refreshFromServer()).thenAnswer((_) async {});
    when(() => tippersViewModel.refreshFromServer()).thenAnswer((_) async {});
    when(() => dauCompsViewModel.selectedDAUComp).thenReturn(comp);

    di.registerSingleton<TippersViewModel>(tippersViewModel);
    di.registerSingleton<DAUCompsViewModel>(dauCompsViewModel);
  });

  tearDown(() async {
    await di.reset();
  });

  test('refreshes server-backed sources before admin scoring', () async {
    when(() => connectedRef.get()).thenAnswer(
      (_) async => _snapshot(exists: true, value: true),
    );
    when(() => probeRef.get()).thenAnswer(
      (_) async => _snapshot(
        exists: true,
        value: <String, Object?>{
          'serverTimestamp': DateTime.now().toUtc().millisecondsSinceEpoch,
        },
      ),
    );
    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: rootDb,
      connectedInfoReference: connectedRef,
      autoInitialize: false,
    );

    await viewModel.prepareFreshAdminScoringInputs(
      comp,
      timeout: const Duration(milliseconds: 200),
    );

    expect(viewModel.adminDatabaseRefreshStatus.isFresh, isTrue);
    expect(viewModel.allTipsViewModel, isNotNull);
    verify(() => tippersViewModel.refreshFromServer()).called(1);
    verify(() => gamesViewModel.refreshFromServer()).called(1);
    verify(() => tipsRef.get()).called(1);
  });

  test('blocks admin scoring refresh when database is not connected', () async {
    when(() => connectedRef.get()).thenAnswer(
      (_) async => _snapshot(exists: true, value: false),
    );
    final viewModel = StatsViewModel(
      comp,
      gamesViewModel,
      database: rootDb,
      connectedInfoReference: connectedRef,
      autoInitialize: false,
    );

    await expectLater(
      viewModel.prepareFreshAdminScoringInputs(
        comp,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      viewModel.adminDatabaseRefreshStatus.state,
      AdminDatabaseRefreshState.failed,
    );
    verifyNever(() => tippersViewModel.refreshFromServer());
    verifyNever(() => gamesViewModel.refreshFromServer());
  });
}

MockDataSnapshot _snapshot({required bool exists, required Object? value}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
