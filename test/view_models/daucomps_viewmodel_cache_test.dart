import 'dart:async';
import 'dart:convert';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/repositories/daucomps_repository.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeDauCompsRepository implements DauCompsRepository {
  _FakeDauCompsRepository(this._controller);

  final StreamController<DatabaseEvent> _controller;

  @override
  Stream<DatabaseEvent> streamDauComps(String daucompsPath) => _controller.stream;

  @override
  Future<String> newCompKey(String daucompsPath) {
    throw UnimplementedError();
  }

  @override
  Future<void> update(Map<String, dynamic> updates) {
    throw UnimplementedError();
  }
}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MockTippersViewModel extends Mock implements TippersViewModel {}

void main() {
  late StreamController<DatabaseEvent> controller;
  late MockTippersViewModel mockTippers;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    controller = StreamController<DatabaseEvent>.broadcast();
    mockTippers = MockTippersViewModel();
    when(() => mockTippers.authenticatedTipper).thenReturn(null);
  });

  tearDown(() async {
    await controller.close();
  });

  test('initial load completes from cached DAUComps in admin mode', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_daucomps_v1': jsonEncode(_compMap(
        dbKey: 'comp-2026',
        name: 'DAU Footy Tipping 2026',
      )),
    });

    final vm = DAUCompsViewModel(
      null,
      true,
      repo: _FakeDauCompsRepository(controller),
      tippers: () => mockTippers,
    );

    await vm.initialDAUCompLoadComplete;

    expect(vm.daucomps, hasLength(1));
    expect(vm.daucomps.first.dbkey, 'comp-2026');
    expect(vm.daucomps.first.name, 'DAU Footy Tipping 2026');

    vm.dispose();
  });

  test('remote snapshot replaces cached DAUComps and refreshes cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cached_daucomps_v1': jsonEncode(_compMap(
        dbKey: 'comp-old',
        name: 'Old Comp',
      )),
    });

    final vm = DAUCompsViewModel(
      null,
      true,
      repo: _FakeDauCompsRepository(controller),
      tippers: () => mockTippers,
    );

    await vm.initialDAUCompLoadComplete;

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: _compMap(
            dbKey: 'comp-new',
            name: 'New Comp',
          ),
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vm.daucomps, hasLength(1));
    expect(vm.daucomps.first.dbkey, 'comp-new');
    expect(vm.daucomps.first.name, 'New Comp');

    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('cached_daucomps_v1');
    expect(cachedJson, isNotNull);
    expect(cachedJson!, contains('comp-new'));

    vm.dispose();
  });
}

MockDatabaseEvent _databaseEvent(DataSnapshot snapshot) {
  final event = MockDatabaseEvent();
  when(() => event.snapshot).thenReturn(snapshot);
  return event;
}

MockDataSnapshot _rootSnapshot({
  required bool exists,
  required Object? value,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}

Map<String, Object?> _compMap({
  required String dbKey,
  required String name,
}) {
  return <String, Object?>{
    dbKey: <String, Object?>{
      p.compNameKey: name,
      p.aflFixtureJsonURLKey: 'https://example.com/afl.json',
      p.nrlFixtureJsonURLKey: 'https://example.com/nrl.json',
      p.combinedRoundsPath: <Map<String, Object?>>[
        <String, Object?>{
          p.roundStartDateKey: '2026-03-01T00:00:00Z',
          p.roundEndDateKey: '2026-03-03T00:00:00Z',
        },
      ],
    },
  };
}
