import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:test/test.dart';

import '../support/fake_mode_store.dart';

/// A clock the test controls: sleeping advances it.
class _Clock {
  int now = 1000000;
  final List<Duration> sleeps = [];

  int read() => now;

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now += d.inMilliseconds;
  }
}

InflightMarker _marker(
  String id, {
  required int startedAtMs,
  String callable = 'link',
}) => InflightMarker(
  operationId: id,
  callable: callable,
  startedAtMs: startedAtMs,
);

void main() {
  group('switching the mode', () {
    test(
      'merges the new fields and logs the change, never replaces the node',
      () async {
        final store = FakeModeStore(
          config: const ServerModeConfig(mode: IdentityMode.coexist),
        );
        final previous = await setIdentityMode(
          store,
          mode: IdentityMode.freeze,
          nowMs: 42,
        );

        expect(previous.mode, IdentityMode.coexist);
        expect(store.updates.single, {
          'mode': 'freeze',
          'changedAtMs': 42,
          'changedBy': 'owner',
        });
        expect(store.log.single, containsPair('from', 'coexist'));
        expect(store.log.single, containsPair('to', 'freeze'));
      },
    );

    test('the pilot list is written sorted, and only when given', () async {
      final store = FakeModeStore();
      await setIdentityMode(
        store,
        mode: IdentityMode.pilot,
        pilotUids: {'b', 'a'},
        nowMs: 1,
      );
      expect(store.updates.single['pilotUids'], ['a', 'b']);

      await setIdentityMode(store, mode: IdentityMode.coexist, nowMs: 2);
      expect(store.updates.last.containsKey('pilotUids'), false);
    });

    test('pilot with nobody to pilot is refused', () async {
      expect(
        () => setIdentityMode(
          FakeModeStore(),
          mode: IdentityMode.pilot,
          nowMs: 1,
        ),
        throwsArgumentError,
      );
      // An existing list is enough.
      final store = FakeModeStore(
        config: const ServerModeConfig(
          mode: IdentityMode.off,
          pilotUids: {'tester'},
        ),
      );
      await setIdentityMode(store, mode: IdentityMode.pilot, nowMs: 1);
    });
  });

  group('the drain', () {
    test('is quiet at once when nothing is in flight', () async {
      final clock = _Clock();
      final result = await drainInflight(
        FakeModeStore(),
        nowMs: clock.read,
        sleep: clock.sleep,
      );
      expect(result.quiet, true);
      expect(clock.sleeps, isEmpty);
    });

    test(
      'waits for a running request and is quiet only after it finishes',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [_marker('slow', startedAtMs: clock.now)],
        );
        store.onInflightRead = (reads) {
          if (reads == 3) {
            store.markers.clear(); // the request finished
          }
        };
        final result = await drainInflight(
          store,
          nowMs: clock.read,
          sleep: clock.sleep,
        );
        expect(result.quiet, true);
        expect(
          clock.sleeps.length,
          3,
          reason: 'it kept polling until a read saw the marker gone',
        );
      },
    );

    test(
      'gives up on a request still running at the deadline, and says it is not quiet',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [_marker('slow', startedAtMs: clock.now)],
        );
        final result = await drainInflight(
          store,
          nowMs: clock.read,
          sleep: clock.sleep,
          maxWait: const Duration(seconds: 10),
          staleAfter: const Duration(minutes: 5),
        );
        expect(result.quiet, false);
        expect(result.stillRunning.single.operationId, 'slow');
        expect(result.stale, isEmpty);
      },
    );

    test(
      'an overdue marker is reported as stale, is NOT removed, and the drain is not quiet',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [
            _marker(
              'old',
              startedAtMs:
                  clock.now - const Duration(minutes: 10).inMilliseconds,
            ),
          ],
        );
        final result = await drainInflight(
          store,
          nowMs: clock.read,
          sleep: clock.sleep,
        );
        expect(result.quiet, false);
        expect(result.stale.single.operationId, 'old');
        expect(
          store.removed,
          isEmpty,
          reason: 'a marker is never deleted on age alone',
        );
        expect(
          clock.sleeps,
          isEmpty,
          reason: 'waiting would not clear it, so it stops at once',
        );
      },
    );

    test('a marker too malformed to age counts as stale', () async {
      final clock = _Clock();
      final store = FakeModeStore(
        markers: [const InflightMarker(operationId: 'odd')],
      );
      final result = await drainInflight(
        store,
        nowMs: clock.read,
        sleep: clock.sleep,
      );
      expect(result.quiet, false);
      expect(result.stale.single.operationId, 'odd');
    });

    test(
      'a late handler that finishes removes its own marker, and the next drain is quiet',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [
            _marker(
              'late',
              startedAtMs:
                  clock.now - const Duration(minutes: 3).inMilliseconds,
            ),
          ],
        );
        expect(
          (await drainInflight(
            store,
            nowMs: clock.read,
            sleep: clock.sleep,
          )).quiet,
          false,
        );
        store.markers.clear(); // the handler finally ended
        expect(
          (await drainInflight(
            store,
            nowMs: clock.read,
            sleep: clock.sleep,
          )).quiet,
          true,
        );
      },
    );

    test(
      'an acknowledged stale marker is removed, and then the drain is quiet',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [
            _marker(
              'old',
              startedAtMs:
                  clock.now - const Duration(minutes: 10).inMilliseconds,
            ),
          ],
        );
        final result = await drainInflight(
          store,
          nowMs: clock.read,
          sleep: clock.sleep,
          acknowledge: {'old'},
        );
        expect(result.quiet, true);
        expect(result.acknowledged, ['old']);
        expect(store.removed, ['old']);
      },
    );

    test('a marker still within its timeout cannot be acknowledged', () async {
      final clock = _Clock();
      final store = FakeModeStore(
        markers: [_marker('fresh', startedAtMs: clock.now)],
      );
      final result = await drainInflight(
        store,
        nowMs: clock.read,
        sleep: clock.sleep,
        maxWait: const Duration(seconds: 4),
        acknowledge: {'fresh', 'unknown'},
      );
      expect(result.acknowledged, isEmpty);
      expect(result.refusedAcknowledgements, containsAll(['fresh', 'unknown']));
      expect(store.removed, isEmpty);
      expect(result.quiet, false);
    });

    test(
      'acknowledging one stale marker leaves the others, which keep it from being quiet',
      () async {
        final clock = _Clock();
        final store = FakeModeStore(
          markers: [
            _marker(
              'a',
              startedAtMs:
                  clock.now - const Duration(minutes: 10).inMilliseconds,
            ),
            _marker(
              'b',
              startedAtMs:
                  clock.now - const Duration(minutes: 10).inMilliseconds,
            ),
          ],
        );
        final result = await drainInflight(
          store,
          nowMs: clock.read,
          sleep: clock.sleep,
          acknowledge: {'a'},
        );
        expect(result.quiet, false);
        expect(result.stale.map((m) => m.operationId), ['b']);
        expect(result.acknowledged, ['a']);
      },
    );
  });

  group('the Firebase CLI store', () {
    late List<List<String>> calls;
    late Map<String, String> answers;

    CliModeStore store() => CliModeStore(
      project: 'demo-project',
      runner: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        final key = arguments.take(2).join(' ');
        return ProcessResult(0, 0, answers[key] ?? 'null', '');
      },
    );

    setUp(() {
      calls = [];
      answers = {};
    });

    test(
      'reads the mode and the in-flight markers with database:get',
      () async {
        answers['database:get /ServerConfig/identity'] = jsonEncode({
          'mode': 'pilot',
          'pilotUids': ['tester'],
          'inflight': {
            'x': {'callable': 'link', 'startedAtMs': 1},
          },
        });
        answers['database:get /ServerConfig/identity/inflight'] = jsonEncode({
          'x': {'callable': 'link', 'startedAtMs': 1},
          'broken': 'nonsense',
        });
        final config = await store().readMode();
        final markers = await store().readInflight();

        expect(config.mode, IdentityMode.pilot);
        expect(config.pilotUids, {'tester'});
        expect(markers.map((m) => m.operationId), ['broken', 'x']);
        expect(
          markers.firstWhere((m) => m.operationId == 'broken').startedAtMs,
          isNull,
        );
        expect(calls.first, [
          'firebase',
          'database:get',
          '/ServerConfig/identity',
          '--project',
          'demo-project',
        ]);
      },
    );

    test('a missing node reads as off with nothing in flight', () async {
      expect((await store().readMode()).mode, IdentityMode.off);
      expect(await store().readInflight(), isEmpty);
    });

    test(
      'updates by merging, logs by key, and removes one marker with --force',
      () async {
        await store().updateIdentityNode({'mode': 'freeze'});
        await store().appendModeLog(7, {'to': 'freeze'});
        await store().removeMarker('abc');

        expect(calls[0], [
          'firebase',
          'database:update',
          '/ServerConfig/identity',
          '--data',
          '{"mode":"freeze"}',
          '--force',
          '--project',
          'demo-project',
        ]);
        expect(calls[1][2], '/ServerConfig/identityModeLog');
        expect(calls[1][4], '{"7":{"to":"freeze"}}');
        expect(calls[2], [
          'firebase',
          'database:remove',
          '/ServerConfig/identity/inflight/abc',
          '--force',
          '--project',
          'demo-project',
        ]);
        expect(
          calls.any((call) => call[1] == 'database:set'),
          false,
          reason: 'set would replace the node and erase the in-flight markers',
        );
      },
    );

    test('a failing command is an error, not a silent success', () async {
      final failing = CliModeStore(
        project: 'p',
        runner: (executable, arguments) async =>
            ProcessResult(0, 1, '', 'permission denied'),
      );
      await expectLater(failing.readMode(), throwsStateError);
    });
  });
  group('reading the in-flight node', () {
    test('a missing node means nothing is running', () {
      expect(parseInflight(null), isEmpty);
      expect(parseInflight(<String, Object?>{}), isEmpty);
    });

    test(
      'anything that is not a set of markers is an error, never a false quiet',
      () {
        for (final bad in [
          'oops',
          7,
          3.5,
          true,
          <Object?>['a', 'b'],
          <Object?>[],
        ]) {
          expect(
            () => parseInflight(bad),
            throwsA(isA<MalformedInflightError>()),
            reason: '$bad',
          );
        }
      },
    );

    test(
      'a malformed entry inside the node is kept as a stale marker, not dropped',
      () {
        final markers = parseInflight({
          'good': {'callable': 'link', 'startedAtMs': 5},
          'bad': 'nonsense',
          'worse': {'callable': 7, 'startedAtMs': 'soon'},
        });
        expect(markers.map((m) => m.operationId), ['bad', 'good', 'worse']);
        expect(
          markers.where((m) => m.startedAtMs == null).map((m) => m.operationId),
          ['bad', 'worse'],
        );
      },
    );

    test(
      'the CLI store raises it too, so the drain cannot report quiet over corrupt data',
      () async {
        final store = CliModeStore(
          project: 'p',
          runner: (executable, arguments) async =>
              ProcessResult(0, 0, '"corrupted"', ''),
        );
        await expectLater(
          store.readInflight(),
          throwsA(isA<MalformedInflightError>()),
        );
      },
    );
  });
}
