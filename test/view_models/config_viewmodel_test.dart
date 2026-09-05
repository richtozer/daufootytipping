import 'dart:async';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/services/app_resume_diagnostics.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDatabaseReference extends Mock implements DatabaseReference {}

class MockDatabaseEvent extends Mock implements DatabaseEvent {}

class MockDataSnapshot extends Mock implements DataSnapshot {}

class MemoryConfigDiagnosticsStorage implements ResumeDiagnosticsStorage {
  final List<String> values = <String>[];

  @override
  Future<void> appendLine(String encodedEvent) async {
    values.add(encodedEvent);
  }

  @override
  Future<List<String>> readLines() async => List<String>.from(values);

  @override
  Future<void> replaceLines(List<String> encodedEvents) async {
    values
      ..clear()
      ..addAll(encodedEvents);
  }
}

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
              p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
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
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
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
            p.cloudFunctionsBaseURLKey: _valueSnapshot('https://example.com'),
            p.adminScoringRescoreURLKey:
                _valueSnapshot('https://rescore.example.com'),
            p.adminCheckFixtureUrlURLKey:
                _valueSnapshot('https://check-fixture-url.example.com'),
          },
        ),
      ),
    );

    await viewModel.initialLoadComplete;

    expect(viewModel.activeDAUComp, 'comp-2026');
    expect(viewModel.createLinkedTipper, isTrue);
    expect(viewModel.minAppVersion, '1.2.3');
    expect(viewModel.googleClientId, 'client-id');
    expect(viewModel.cloudFunctionsBaseURL, 'https://example.com');
    expect(viewModel.adminScoringRescoreURL, 'https://rescore.example.com');
    expect(
      viewModel.adminCheckFixtureUrlURL,
      'https://check-fixture-url.example.com',
    );

    viewModel.dispose();
  });

  test(
    'records the resume probe value from the existing config listener',
    () async {
      final MemoryConfigDiagnosticsStorage storage =
          MemoryConfigDiagnosticsStorage();
      final ResumeDiagnosticsRecorder recorder = ResumeDiagnosticsRecorder(
        storage: storage,
        processId: 'config-diagnostics-test',
      );
      await recorder.initialize();
      AppResumeDiagnostics.installRecorderForTest(recorder);
      addTearDown(AppResumeDiagnostics.resetForTest);

      final ConfigViewModel viewModel = ConfigViewModel(
        db: mockDb,
        initialLoadTimeout: const Duration(seconds: 1),
      );
      controller.add(
        _databaseEvent(
          _rootSnapshot(
            exists: true,
            value: <String, Object?>{
              p.currentDAUCompKey: 'comp-2026',
              p.createLinkedTipperKey: true,
              AppResumeDiagnostics.configProbeKey: 'config-nonce-1',
            },
            children: <String, Object?>{
              p.currentDAUCompKey: _valueSnapshot('comp-2026'),
              p.createLinkedTipperKey: _valueSnapshot(true),
              p.minAppVersionKey: _valueSnapshot('1.4.0'),
              p.googleClientIdKey: _valueSnapshot('client-id'),
              p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
            },
          ),
        ),
      );

      await viewModel.initialLoadComplete;
      await recorder.flush();

      final ResumeDiagnosticEvent event = (await recorder.readEvents())
          .singleWhere(
            (event) => event.stage == 'config_listener_snapshot_received',
          );
      expect(event.details['resumeProbePresent'], isTrue);
      expect(event.details['resumeProbe'], 'config-nonce-1');

      viewModel.dispose();
    },
  );

  test('loads the rescore URL directly when the cached snapshot lacks it', () async {
    final childReference = MockDatabaseReference();
    final snapshot = MockDataSnapshot();
    when(() => mockDb.child(p.adminScoringRescoreURLKey))
        .thenReturn(childReference);
    when(() => childReference.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.value)
        .thenReturn('https://admin-scoring-rescore.example.com');
    final viewModel = ConfigViewModel(
      db: mockDb,
      initialLoadTimeout: const Duration(seconds: 1),
    );

    final value = await viewModel.loadAdminScoringRescoreURL();

    expect(value, 'https://admin-scoring-rescore.example.com');
    expect(viewModel.adminScoringRescoreURL, value);
    verify(() => childReference.get()).called(1);

    viewModel.dispose();
  });

  test('loads the check-fixture-url URL directly when the cached snapshot lacks it', () async {
    final childReference = MockDatabaseReference();
    final snapshot = MockDataSnapshot();
    when(() => mockDb.child(p.adminCheckFixtureUrlURLKey))
        .thenReturn(childReference);
    when(() => childReference.get()).thenAnswer((_) async => snapshot);
    when(() => snapshot.value)
        .thenReturn('https://admin-check-fixture-url.example.com');
    final viewModel = ConfigViewModel(
      db: mockDb,
      initialLoadTimeout: const Duration(seconds: 1),
    );

    final value = await viewModel.loadAdminCheckFixtureUrlURL();

    expect(value, 'https://admin-check-fixture-url.example.com');
    expect(viewModel.adminCheckFixtureUrlURL, value);
    verify(() => childReference.get()).called(1);

    viewModel.dispose();
  });

  test('config values prefer the materialized root snapshot', () async {
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
            p.createLinkedTipperKey: true,
            p.cloudFunctionsBaseURLKey: 'https://functions.example.com',
          },
          children: <String, Object?>{
            p.currentDAUCompKey: _valueSnapshot('comp-2026'),
            p.createLinkedTipperKey: _valueSnapshot(true),
            p.minAppVersionKey: _valueSnapshot(null),
            p.googleClientIdKey: _valueSnapshot(null),
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
          },
        ),
      ),
    );

    await viewModel.initialLoadComplete;

    expect(
      viewModel.cloudFunctionsBaseURL,
      'https://functions.example.com',
    );

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
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
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
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
          },
        ),
      ),
    );

    await viewModel.initialLoadComplete;

    expect(viewModel.activeDAUComp, 'comp-2026');
    expect(viewModel.createLinkedTipper, isTrue);

    viewModel.dispose();
  });

  test('retryInitialLoad re-arms startup after a failed initial load', () async {
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
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
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

    await viewModel.retryInitialLoad();

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
            p.cloudFunctionsBaseURLKey: _valueSnapshot(null),
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
    final child = children[key];
    return child is DataSnapshot ? child : _valueSnapshot(null);
  });
  return snapshot;
}

MockDataSnapshot _valueSnapshot(Object? value) {
  final snapshot = MockDataSnapshot();
  when(() => snapshot.value).thenReturn(value);
  return snapshot;
}
