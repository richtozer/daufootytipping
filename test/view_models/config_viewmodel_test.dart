import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

void main() {
  late MockDatabaseReference mockDb;
  late StreamController<DatabaseEvent> controller;

  setUp(() {
    mockDb = MockDatabaseReference();
    controller = StreamController<DatabaseEvent>.broadcast();
    when(() => mockDb.onValue).thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  test(
    'initial load stays pending while bootstrap config is incomplete',
    () async {
      final viewModel = ConfigViewModel(
        db: mockDb,
        initialLoadTimeout: const Duration(seconds: 1),
      );

      controller.add(
        _databaseEvent(
          _rootSnapshot(
            exists: true,
            value: <String, Object?>{
              p.currentDAUCompKey: 'comp-2026',
            },
            children: <String, Object?>{
              p.currentDAUCompKey: _valueSnapshot('comp-2026'),
              p.createLinkedTipperKey: _valueSnapshot(null),
              p.minAppVersionKey: _valueSnapshot(null),
              p.googleClientIdKey: _valueSnapshot(null),
            },
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(viewModel.activeDAUComp, 'comp-2026');
      expect(viewModel.createLinkedTipper, isNull);
      expect(
        viewModel.initialLoadComplete.timeout(const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );

      viewModel.dispose();
    },
  );

  test('initial load completes once required bootstrap config arrives', () async {
    final viewModel = ConfigViewModel(
      db: mockDb,
      initialLoadTimeout: const Duration(seconds: 1),
    );

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: <String, Object?>{
            p.currentDAUCompKey: 'comp-2026',
          },
          children: <String, Object?>{
            p.currentDAUCompKey: _valueSnapshot('comp-2026'),
            p.createLinkedTipperKey: _valueSnapshot(null),
            p.minAppVersionKey: _valueSnapshot(null),
            p.googleClientIdKey: _valueSnapshot(null),
          },
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: <String, Object?>{
            p.currentDAUCompKey: 'comp-2026',
            p.createLinkedTipperKey: true,
          },
          children: <String, Object?>{
            p.currentDAUCompKey: _valueSnapshot('comp-2026'),
            p.createLinkedTipperKey: _valueSnapshot(true),
            p.minAppVersionKey: _valueSnapshot('1.2.3'),
            p.googleClientIdKey: _valueSnapshot('client-id'),
          },
        ),
      ),
    );

    await viewModel.initialLoadComplete;

    expect(viewModel.activeDAUComp, 'comp-2026');
    expect(viewModel.createLinkedTipper, isTrue);
    expect(viewModel.minAppVersion, '1.2.3');
    expect(viewModel.googleClientId, 'client-id');

    viewModel.dispose();
  });

  test('initial load reports timeout when bootstrap config never arrives', () async {
    final viewModel = ConfigViewModel(
      db: mockDb,
      initialLoadTimeout: const Duration(milliseconds: 20),
    );

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: <String, Object?>{},
          children: <String, Object?>{
            p.currentDAUCompKey: _valueSnapshot(null),
            p.createLinkedTipperKey: _valueSnapshot(null),
            p.minAppVersionKey: _valueSnapshot(null),
            p.googleClientIdKey: _valueSnapshot(null),
          },
        ),
      ),
    );

    await expectLater(
      viewModel.initialLoadComplete,
      throwsA(
        predicate<Object?>(
          (error) => error.toString().contains('Config load timed out'),
        ),
      ),
    );

    viewModel.dispose();
  });

  test('retryable startup read errors reconnect and recover on a later snapshot', () async {
    final viewModel = ConfigViewModel(
      db: mockDb,
      initialLoadTimeout: const Duration(seconds: 1),
      retryableStartupReconnectDelay: const Duration(milliseconds: 5),
      maxRetryableStartupReconnectAttempts: 2,
    );

    controller.addError(
      '[firebase_database/permission-denied] App Check token rejected by Play Integrity.',
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    controller.add(
      _databaseEvent(
        _rootSnapshot(
          exists: true,
          value: <String, Object?>{
            p.currentDAUCompKey: 'comp-2026',
            p.createLinkedTipperKey: true,
          },
          children: <String, Object?>{
            p.currentDAUCompKey: _valueSnapshot('comp-2026'),
            p.createLinkedTipperKey: _valueSnapshot(true),
            p.minAppVersionKey: _valueSnapshot('1.2.3'),
            p.googleClientIdKey: _valueSnapshot('client-id'),
          },
        ),
      ),
    );

    await viewModel.initialLoadComplete;

    expect(viewModel.activeDAUComp, 'comp-2026');
    expect(viewModel.createLinkedTipper, isTrue);

    viewModel.dispose();
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
  required Map<String, Object?> children,
}) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.exists).thenReturn(exists);
  when(() => snapshot.value).thenReturn(value);
  when(() => snapshot.child(any())).thenAnswer((invocation) {
    final key = invocation.positionalArguments.single as String;
    return children[key] as DataSnapshot;
  });
  return snapshot;
}

MockDataSnapshot _valueSnapshot(Object? value) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
