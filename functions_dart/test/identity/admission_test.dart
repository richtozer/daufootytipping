import 'dart:async';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/emulator.dart';

/// Fails the requests the test selects, to prove the wrapper fails closed.
class _SelectiveFailure extends http.BaseClient {
  _SelectiveFailure(this._inner, this._fail);

  final http.Client _inner;
  final bool Function(http.BaseRequest request) _fail;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_fail(request)) {
      throw http.ClientException('injected failure', request.url);
    }
    return _inner.send(request);
  }
}

/// Holds the requests the test selects until it opens the gate, then forwards
/// them: a request that outlives the caller that gave up on it.
class _Gate extends http.BaseClient {
  _Gate(this._inner, this._hold);

  final http.Client _inner;
  final bool Function(http.BaseRequest request) _hold;
  final Completer<void> _open = Completer<void>();

  void open() => _open.complete();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_hold(request)) {
      await _open.future;
    }
    return _inner.send(request);
  }
}

Future<void> _eventually(
  Future<bool> Function() check, {
  Duration within = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(within);
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $within');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<Map<String, Object?>> _markers(RestDatabase database) async {
  final value = (await database.ref(inflightPath).once()).value;
  return value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};
}

void main() {
  final skip = emulatorSkipReason;

  group('admission against a real database', () {
    late final RestDatabase database = openEmulatorDatabase();
    late List<String> log;

    setUp(() async {
      await clearEmulatorDatabase(database);
      log = [];
    });

    Future<void> setMode(String mode, {List<String>? pilotUids}) => database
        .ref(identityModePath)
        .update({'mode': mode, 'pilotUids': ?pilotUids});

    Future<T> admitted<T>(
      Future<T> Function(Admission admission) body, {
      String uid = 'user-1',
      RestDatabase? on,
      Future<void> Function()? afterMarkerWritten,
    }) => runAdmitted<T>(
      database: on ?? database,
      callable: 'link-or-create-tipper',
      uid: uid,
      body: body,
      log: log.add,
      afterMarkerWritten: afterMarkerWritten,
    );

    test(
      'the marker is written before the body runs, and removed after',
      () async {
        await setMode('coexist');
        Map<String, Object?>? during;
        final result = await admitted((admission) async {
          during = await _markers(database);
          return admission.operationId;
        });

        expect(during!.keys, [result]);
        expect((during![result]! as Map)['callable'], 'link-or-create-tipper');
        expect((during![result]! as Map)['startedAtMs'], isA<int>());
        expect(await _markers(database), isEmpty);
      },
      skip: skip,
    );

    test('the marker is written BEFORE the mode is read', () async {
      await setMode('coexist');
      Map<String, Object?>? atModeRead;
      await admitted(
        (_) async {},
        afterMarkerWritten: () async => atModeRead = await _markers(database),
      );
      expect(
        atModeRead,
        hasLength(1),
        reason: 'visible to a drain before the mode was looked at',
      );
    }, skip: skip);

    test('the body is told the mode it was admitted under', () async {
      await setMode('final');
      final mode = await admitted((admission) async => admission.config.mode);
      expect(mode, IdentityMode.finalShape);
    }, skip: skip);

    test(
      'the marker is removed when the body throws, and the error is kept',
      () async {
        await setMode('coexist');
        await expectLater(
          admitted(
            (_) async => throw AbortedError('busy', reason: identityReasonBusy),
          ),
          throwsA(isA<AbortedError>()),
        );
        expect(await _markers(database), isEmpty);
        expect(log.last, contains('outcome=error'));
      },
      skip: skip,
    );

    test(
      'a missing mode is off: refused, the body never runs, the marker is removed',
      () async {
        var ran = false;
        await expectLater(
          admitted((_) async => ran = true),
          throwsA(isA<FailedPreconditionError>()),
        );
        expect(ran, false);
        expect(await _markers(database), isEmpty);
        expect(log.last, contains('outcome=refused'));
      },
      skip: skip,
    );

    test('an unknown mode string is off', () async {
      await setMode('banana');
      await expectLater(
        admitted((_) async {}),
        throwsA(isA<FailedPreconditionError>()),
      );
    }, skip: skip);

    test(
      'off, pilot and freeze refuse as the plan says; coexist and final admit',
      () async {
        await setMode('off');
        await expectLater(
          admitted((_) async {}),
          throwsA(isA<FailedPreconditionError>()),
        );

        await setMode('pilot', pilotUids: ['tester']);
        await expectLater(
          admitted((_) async {}, uid: 'stranger'),
          throwsA(isA<FailedPreconditionError>()),
        );
        await admitted((_) async {}, uid: 'tester');

        await setMode('freeze');
        await expectLater(
          admitted((_) async {}),
          throwsA(isA<UnavailableError>()),
        );

        await setMode('coexist');
        await admitted((_) async {});
        await setMode('final');
        await admitted((_) async {});
        expect(await _markers(database), isEmpty);
      },
      skip: skip,
    );

    test(
      'a mode change between the marker and the mode read is honoured',
      () async {
        await setMode('coexist');
        var ran = false;
        await expectLater(
          admitted(
            (_) async => ran = true,
            afterMarkerWritten: () => setMode('freeze'),
          ),
          throwsA(isA<UnavailableError>()),
        );
        expect(
          ran,
          false,
          reason: 'the freeze was written before the mode was read',
        );
        expect(await _markers(database), isEmpty);
      },
      skip: skip,
    );

    test('it fails closed when the marker cannot be written', () async {
      await setMode('coexist');
      final failing = openEmulatorDatabase(
        wrap: (inner) => _SelectiveFailure(
          inner,
          (request) =>
              request.method == 'PUT' &&
              request.url.path.contains('/inflight/'),
        ),
      );
      var ran = false;
      await expectLater(
        admitted((_) async => ran = true, on: failing),
        throwsA(isA<UnavailableError>()),
      );
      expect(ran, false);
      expect(log.single, contains('marker not written'));
    }, skip: skip);

    test(
      'it fails closed when the mode cannot be read, and tidies its marker',
      () async {
        await setMode('coexist');
        final failing = openEmulatorDatabase(
          wrap: (inner) => _SelectiveFailure(
            inner,
            (request) =>
                request.method == 'GET' &&
                request.url.path.endsWith('/identity/mode.json'),
          ),
        );
        var ran = false;
        await expectLater(
          admitted((_) async => ran = true, on: failing),
          throwsA(isA<UnavailableError>()),
        );
        expect(ran, false);
        expect(await _markers(database), isEmpty);
      },
      skip: skip,
    );

    test(
      'if the marker cannot be removed it is left behind, loudly, and the result still returns',
      () async {
        await setMode('coexist');
        final failing = openEmulatorDatabase(
          wrap: (inner) => _SelectiveFailure(
            inner,
            (request) =>
                request.method == 'DELETE' &&
                request.url.path.contains('/inflight/'),
          ),
        );
        final result = await admitted((_) async => 'done', on: failing);
        expect(result, 'done');
        expect(
          await _markers(database),
          hasLength(1),
          reason: 'left for the drain to report as stale',
        );
        expect(log.any((line) => line.contains('marker left behind')), true);
      },
      skip: skip,
    );

    test('logs a start line and an end line carrying the operation id', () async {
      await setMode('coexist');
      final id = await admitted((admission) async => admission.operationId);
      expect(
        log.first,
        '[identity] start op=$id callable=link-or-create-tipper',
      );
      expect(
        log.last,
        '[identity] end op=$id callable=link-or-create-tipper outcome=ok writesSettled=true',
      );
    }, skip: skip);
  });

  group('the drain, with the real admission code', () {
    late final RestDatabase database = openEmulatorDatabase();
    late RestModeStore store;
    var now = 0;

    setUp(() async {
      await clearEmulatorDatabase(database);
      store = RestModeStore(database);
      now = DateTime.now().millisecondsSinceEpoch;
    });

    test(
      'a slow request admitted before a freeze finishes; a request after it is refused; the drain waits for the slow one',
      () async {
        await database.ref(identityModePath).update({'mode': 'coexist'});
        final slowStarted = Completer<void>();
        final release = Completer<void>();
        final slow = runAdmitted<String>(
          database: database,
          callable: 'link-or-create-tipper',
          uid: 'slow-user',
          log: (_) {},
          body: (admission) async {
            slowStarted.complete();
            await release.future;
            return 'slow finished';
          },
        );
        await slowStarted.future;

        await setIdentityMode(store, mode: IdentityMode.freeze, nowMs: now);

        // A request that starts after the mode change is refused.
        await expectLater(
          runAdmitted<void>(
            database: database,
            callable: 'update-tipper-alias',
            uid: 'late-user',
            log: (_) {},
            body: (_) async {},
          ),
          throwsA(isA<UnavailableError>()),
        );

        // The drain sees the slow request and waits; it finishes while the drain polls.
        var polls = 0;
        final result = await drainInflight(
          store,
          nowMs: () => DateTime.now().millisecondsSinceEpoch,
          pollInterval: const Duration(milliseconds: 20),
          sleep: (d) async {
            polls += 1;
            if (polls == 3) {
              release.complete();
              await slow;
            }
            await Future<void>.delayed(d);
          },
        );

        expect(await slow, 'slow finished');
        expect(
          polls,
          greaterThanOrEqualTo(3),
          reason: 'it waited for the slow request',
        );
        expect(result.quiet, true);
        expect(await _markers(database), isEmpty);
      },
      skip: emulatorSkipReason,
    );

    test(
      'a request whose marker is left behind keeps the drain from ever reporting quiet',
      () async {
        await database.ref(identityModePath).update({'mode': 'coexist'});
        final failing = openEmulatorDatabase(
          wrap: (inner) => _SelectiveFailure(
            inner,
            (request) =>
                request.method == 'DELETE' &&
                request.url.path.contains('/inflight/'),
          ),
        );
        await runAdmitted<void>(
          database: failing,
          callable: 'register-device-token',
          uid: 'u',
          log: (_) {},
          body: (_) async {},
        );

        final result = await drainInflight(
          store,
          // Ninety-one seconds on: the marker is now overdue.
          nowMs: () => now + 91 * 1000,
          sleep: (_) async {},
        );
        expect(result.quiet, false);
        expect(result.stale, hasLength(1));
        expect(
          await _markers(database),
          hasLength(1),
          reason: 'never deleted on age alone',
        );

        final operationId = result.stale.single.operationId;
        final cleared = await drainInflight(
          store,
          nowMs: () => now + 91 * 1000,
          sleep: (_) async {},
          acknowledge: {operationId},
        );
        expect(cleared.quiet, true);
        expect(await _markers(database), isEmpty);
      },
      skip: emulatorSkipReason,
    );

    test('the CLI store and the REST store agree on what is stored', () async {
      await setIdentityMode(
        store,
        mode: IdentityMode.pilot,
        pilotUids: {'b', 'a'},
        nowMs: 99,
      );
      final stored = (await database.ref(identityModePath).once()).value as Map;
      expect(stored['mode'], 'pilot');
      expect(stored['pilotUids'], ['a', 'b']);
      expect((await readServerMode(database)).pilotUids, {'a', 'b'});
      final log = (await database.ref(identityModeLogPath).once()).value as Map;
      expect((log['99'] as Map)['to'], 'pilot');

      // A later change merges: the in-flight markers beneath the node survive.
      await database.ref('$inflightPath/keep').set({
        'callable': 'x',
        'startedAtMs': now,
      });
      await setIdentityMode(store, mode: IdentityMode.coexist, nowMs: 100);
      expect((await _markers(database)).keys, ['keep']);
    }, skip: emulatorSkipReason);
  });
  group('a write that outlives the handler', () {
    late final RestDatabase database = openEmulatorDatabase();
    late List<String> log;

    setUp(() async {
      await clearEmulatorDatabase(database);
      await database.ref(identityModePath).update({'mode': 'coexist'});
      log = [];
    });

    test(
      'keeps the marker, so the drain is never quiet while the write is still on its way',
      () async {
        late _Gate held;
        final gated = openEmulatorDatabase(
          requestTimeout: const Duration(milliseconds: 200),
          wrap: (inner) => held = _Gate(
            inner,
            (request) =>
                request.method == 'PUT' &&
                request.url.path.contains('/Scratch/'),
          ),
        );

        // The handler's write is held; the handler gives up after 200 ms and exits with an error.
        await expectLater(
          runAdmitted<void>(
            database: gated,
            callable: 'link-or-create-tipper',
            uid: 'user-1',
            log: log.add,
            writeSettleGrace: const Duration(milliseconds: 300),
            body: (_) async => gated.ref('/Scratch/x').set('late'),
          ),
          throwsA(isA<UnavailableError>()),
        );

        // The handler has ended, but its end line says its write has not settled...
        expect(log.any((line) => line.contains('writesSettled=false')), true);
        expect(log.any((line) => line.contains('marker kept')), true);
        // ...the marker is still there...
        expect(await _markers(database), hasLength(1));
        // ...the write has not reached the database...
        expect((await database.ref('/Scratch/x').once()).value, isNull);

        // ...and the drain does not call that quiet.
        final store = RestModeStore(database);
        final during = await drainInflight(
          store,
          nowMs: () => DateTime.now().millisecondsSinceEpoch,
          pollInterval: const Duration(milliseconds: 20),
          maxWait: const Duration(milliseconds: 150),
          sleep: (d) => Future<void>.delayed(d),
        );
        expect(during.quiet, false);
        expect(during.stillRunning, hasLength(1));

        // The request completes afterwards, and it does land: the risk was real.
        held.open();
        await _eventually(
          () async => (await database.ref('/Scratch/x').once()).value == 'late',
        );
        await _eventually(() async => (await _markers(database)).isEmpty);
        expect(log.any((line) => line.contains('marker cleared')), true);

        final after = await drainInflight(
          store,
          nowMs: () => DateTime.now().millisecondsSinceEpoch,
          sleep: (d) => Future<void>.delayed(d),
        );
        expect(
          after.quiet,
          true,
          reason: 'quiet only once the write had settled',
        );
      },
      skip: skip,
    );

    test(
      'a marker write that times out and lands late is tidied up once it does',
      () async {
        late _Gate held;
        final gated = openEmulatorDatabase(
          requestTimeout: const Duration(milliseconds: 200),
          wrap: (inner) => held = _Gate(
            inner,
            (request) =>
                request.method == 'PUT' &&
                request.url.path.contains('/inflight/'),
          ),
        );
        var ran = false;
        await expectLater(
          runAdmitted<void>(
            database: gated,
            callable: 'link-or-create-tipper',
            uid: 'user-1',
            log: log.add,
            body: (_) async => ran = true,
          ),
          throwsA(isA<UnavailableError>()),
        );
        expect(ran, false);

        held.open(); // the marker write reaches the database after the request was refused
        await _eventually(
          () async => log.any((line) => line.contains('marker cleared')),
        );
        expect(
          await _markers(database),
          isEmpty,
          reason: 'nobody owns that marker, so it is removed',
        );
      },
      skip: skip,
    );

    test(
      'a handler whose writes all finished clears its marker at once',
      () async {
        await runAdmitted<void>(
          database: database,
          callable: 'link-or-create-tipper',
          uid: 'user-1',
          log: log.add,
          body: (_) async => database.ref('/Scratch/y').set(1),
        );
        expect(log.last, contains('writesSettled=true'));
        expect(await _markers(database), isEmpty);
      },
      skip: skip,
    );
  });
}
