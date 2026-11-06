import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/emulator.dart';

/// Replays canned responses so the conditional-write behaviour can be checked
/// without a database: what the handle sends and what it does with 412 and a
/// missing ETag.
class _Script {
  _Script(this._responses);

  final List<http.Response> _responses;
  final List<http.Request> requests = [];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return _responses.removeAt(0);
  });
}

http.Response _read(Object? body, {String? etag = 'etag-1'}) =>
    http.Response(jsonEncode(body), 200, headers: {'etag': ?etag});

RestDatabaseReference _ref(http.Client client) => RestDatabaseReference(
  client: client,
  databaseUrl: 'https://example.invalid',
  path: '/Slot',
  random: Random(1),
);

void main() {
  group('RestDatabaseReference.atomicUpdate (scripted responses)', () {
    test('writes with if-match set to the ETag it read', () async {
      final script = _Script([_read(null, etag: 'null_etag'), _read('mine')]);
      final result = await _ref(
        script.client,
      ).atomicUpdate((current) => 'mine');

      expect(result.applied, isTrue);
      expect(result.value, 'mine');
      expect(script.requests.first.headers['X-Firebase-ETag'], 'true');
      expect(script.requests.last.method, 'PUT');
      expect(script.requests.last.headers['if-match'], 'null_etag');
    });

    test('fails closed when the database returns no ETag', () async {
      final script = _Script([_read(null, etag: null)]);

      await expectLater(
        _ref(script.client).atomicUpdate((current) => 'mine'),
        throwsA(
          isA<InternalError>().having(
            (error) => error.toString(),
            'message',
            contains('no ETag'),
          ),
        ),
      );
      expect(
        script.requests.where((request) => request.method == 'PUT'),
        isEmpty,
        reason: 'it must not fall back to an unconditional write',
      );
    });

    test('keepCurrentValue writes nothing and reports what it read', () async {
      final script = _Script([_read('someone')]);
      final result = await _ref(
        script.client,
      ).atomicUpdate((current) => keepCurrentValue);

      expect(result.applied, isFalse);
      expect(result.value, 'someone');
      expect(script.requests, hasLength(1));
    });

    test('a 412 re-reads, decides again and retries the write', () async {
      final script = _Script([
        _read(null, etag: 'a'),
        http.Response('', 412),
        _read('other', etag: 'b'),
        _read('mine'),
      ]);
      final seen = <Object?>[];
      final result = await _ref(script.client).atomicUpdate((current) {
        seen.add(current);
        return 'mine';
      });

      expect(seen, [null, 'other']);
      expect(result.applied, isTrue);
      expect(script.requests.last.headers['if-match'], 'b');
    });

    test('gives up with an aborted error when it keeps losing', () async {
      final losing = List<http.Response>.generate(
        200,
        (index) => index.isEven ? _read(null) : http.Response('', 412),
      );
      final script = _Script(losing);

      await expectLater(
        _ref(script.client).atomicUpdate(
          (current) => 'mine',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<AbortedError>()),
      );
    });

    test('other failures are internal errors, never retried', () async {
      final script = _Script([_read(null), http.Response('denied', 401)]);

      await expectLater(
        _ref(script.client).atomicUpdate((current) => 'mine'),
        throwsA(isA<InternalError>()),
      );
      expect(script.requests, hasLength(2));
    });
  });

  group(
    'RestDatabaseReference against the emulator',
    skip: emulatorSkipReason,
    () {
      late RestDatabase database;

      setUp(() async {
        database = openEmulatorDatabase();
        await clearEmulatorDatabase(database);
      });

      test(
        'the emulator supports the conditional writes the handle relies on',
        () async {
          final slot = database.ref('/Probe/slot');
          final first = await slot.atomicUpdate((current) => 'tipper-1');
          expect(first.applied, isTrue);
          expect((await slot.once()).value, 'tipper-1');
        },
      );

      test(
        'of 25 racing writers exactly one sees an empty slot and wins',
        () async {
          final slot = database.ref('/Probe/race');
          final outcomes = await Future.wait(
            List.generate(25, (index) async {
              final result = await slot.atomicUpdate(
                (current) =>
                    current == null ? 'writer-$index' : keepCurrentValue,
              );
              return result.applied;
            }),
          );

          expect(outcomes.where((won) => won), hasLength(1));
          expect((await slot.once()).value, startsWith('writer-'));
        },
      );

      test(
        'every increment survives 20 concurrent read-modify-writes',
        () async {
          final counter = database.ref('/Probe/counter');
          await Future.wait(
            List.generate(
              20,
              (index) => counter.atomicUpdate(
                (current) => ((current as int?) ?? 0) + 1,
                timeout: const Duration(seconds: 20),
              ),
            ),
          );

          expect((await counter.once()).value, 20);
        },
      );

      test('null deletes and remove clears a subtree', () async {
        final slot = database.ref('/Probe/tree/leaf');
        await slot.set('x');
        await slot.atomicUpdate((current) => null);
        expect((await slot.once()).value, isNull);

        await slot.set('y');
        await database.ref('/Probe').remove();
        expect((await database.ref('/Probe').once()).value, isNull);
      });

      test('runTransaction keeps its firebase_dart style contract', () async {
        final slot = database.ref('/Probe/legacy');
        final committed = await slot.runTransaction((data) async {
          data.value = 'locked';
          return data;
        });
        expect(committed.committed, isTrue);
        expect(committed.dataSnapshot?.value, 'locked');

        final aborted = await slot.runTransaction((data) async => null);
        expect(aborted.committed, isFalse);
        expect(aborted.dataSnapshot?.value, 'locked');
      });

      test(
        'child builds nested paths and update writes several keys',
        () async {
          final parent = database.ref('/Probe/parent');
          await parent.update({'a': 1, 'b/c': 2});
          expect((await parent.child('a').once()).value, 1);
          expect((await parent.child('b').child('c').once()).value, 2);
        },
      );
    },
  );
  group('WriteLedger', () {
    test(
      'counts a write from the moment it is sent until it finishes, either way',
      () async {
        final ledger = WriteLedger();
        final ok = Completer<int>();
        final failing = Completer<int>();
        ledger.track(() => ok.future);
        ledger.track(() => failing.future).ignore();
        expect(ledger.pendingCount, 2);

        ok.complete(1);
        await Future<void>.delayed(Duration.zero);
        expect(ledger.pendingCount, 1);

        failing.completeError(StateError('boom'));
        await Future<void>.delayed(Duration.zero);
        expect(ledger.pendingCount, 0);
      },
    );

    test('settled is true at once when nothing is pending', () async {
      expect(
        await WriteLedger().settled(timeout: const Duration(seconds: 1)),
        true,
      );
    });

    test(
      'settled waits for the last write, and gives up with false at the timeout',
      () async {
        final ledger = WriteLedger();
        final slow = Completer<void>();
        ledger.track(() => slow.future);

        expect(
          await ledger.settled(timeout: const Duration(milliseconds: 50)),
          false,
        );
        expect(
          ledger.pendingCount,
          1,
          reason: 'giving up on waiting does not stop the write',
        );

        final waiting = ledger.settled(timeout: const Duration(seconds: 2));
        slow.complete();
        expect(await waiting, true);
      },
    );

    test(
      'a timed-out REST write stays pending until the request itself finishes',
      () async {
        final release = Completer<http.Response>();
        final client = MockClient((request) => release.future);
        final database = RestDatabase(
          client: client,
          databaseUrl: 'https://example.invalid',
          requestTimeout: const Duration(milliseconds: 50),
        );

        await expectLater(
          database.ref('/Slot').set('x'),
          throwsA(isA<UnavailableError>()),
        );
        expect(
          database.writes.pendingCount,
          1,
          reason: 'the caller gave up; the request did not',
        );

        release.complete(http.Response('null', 200));
        expect(
          await database.writes.settled(timeout: const Duration(seconds: 2)),
          true,
        );
      },
    );

    test(
      'reads are not tracked, because a read that outlives its caller changes nothing',
      () async {
        final client = MockClient(
          (request) async => http.Response('null', 200),
        );
        final database = RestDatabase(
          client: client,
          databaseUrl: 'https://example.invalid',
        );
        await database.ref('/Slot').once();
        expect(database.writes.pendingCount, 0);
      },
    );

    group('outcomes', () {
      Future<RestDatabase> databaseAnswering(
        Future<http.Response> Function(http.Request request) answer,
      ) async => RestDatabase(
        client: MockClient(answer),
        databaseUrl: 'https://example.invalid',
      );

      test('a 2xx is a known outcome', () async {
        final database = await databaseAnswering(
          (request) async => http.Response('null', 200),
        );
        await database.ref('/Slot').set('x');
        expect(database.writes.uncertainCount, 0);
      });

      test('a 4xx is a known outcome: it was not applied', () async {
        final database = await databaseAnswering(
          (request) async => http.Response('{"error":"denied"}', 403),
        );
        await expectLater(
          database.ref('/Slot').set('x'),
          throwsA(isA<InternalError>()),
        );
        expect(database.writes.uncertainCount, 0);
      });

      test('a lost compare-and-set (412) is a known outcome', () async {
        var attempt = 0;
        final database = await databaseAnswering((request) async {
          if (request.method == 'GET') {
            return _read('v', etag: 'e${++attempt}');
          }
          return attempt < 2
              ? http.Response('null', 412)
              : http.Response('"w"', 200);
        });
        final result = await database
            .ref('/Slot')
            .atomicUpdate((current) => 'w');
        expect(result.applied, true);
        expect(database.writes.uncertainCount, 0);
      });

      test('a 5xx is not: the write may have been applied', () async {
        final database = await databaseAnswering(
          (request) async => http.Response('', 503),
        );
        await expectLater(
          database.ref('/Slot').set('x'),
          throwsA(isA<InternalError>()),
        );
        expect(database.writes.uncertainCount, 1);
      });

      test(
        'a transport error is not: the response may be what was lost',
        () async {
          final database = await databaseAnswering(
            (request) async => throw http.ClientException('reset'),
          );
          await expectLater(
            database.ref('/Slot').remove(),
            throwsA(isA<http.ClientException>()),
          );
          expect(database.writes.uncertainCount, 1);
          expect(database.writes.pendingCount, 0);
          expect(
            await database.writes.settled(timeout: const Duration(seconds: 1)),
            true,
            reason:
                'settled says the write finished, not that its outcome is known',
          );
        },
      );

      test(
        'a read that fails is not a write, so it counts for nothing',
        () async {
          final database = await databaseAnswering(
            (request) async => throw http.ClientException('reset'),
          );
          await expectLater(
            database.ref('/Slot').once(),
            throwsA(isA<http.ClientException>()),
          );
          expect(database.writes.uncertainCount, 0);
        },
      );
    });

    group('the write fence', () {
      test('is asked before every write and can refuse it', () async {
        final sent = <String>[];
        final database = RestDatabase(
          client: MockClient((request) async {
            sent.add(request.method);
            return http.Response('null', 200);
          }),
          databaseUrl: 'https://example.invalid',
        );
        var open = true;
        database.writes.fence = () {
          if (!open) {
            throw UnavailableError('closed');
          }
        };

        await database.ref('/Slot').set('x');
        await database.ref('/Slot').update({'a': 1});
        await database.ref('/Slot').remove();
        expect(sent, ['PUT', 'PATCH', 'DELETE']);

        open = false;
        for (final write in <Future<void> Function()>[
          () => database.ref('/Slot').set('y'),
          () => database.ref('/Slot').update({'a': 2}),
          () => database.ref('/Slot').remove(),
        ]) {
          await expectLater(write(), throwsA(isA<UnavailableError>()));
        }
        expect(sent, hasLength(3), reason: 'a refused write is never sent');
        expect(database.writes.pendingCount, 0);
        expect(database.writes.uncertainCount, 0);
      });

      test(
        'also stops the write half of a compare-and-set, not its read',
        () async {
          final sent = <String>[];
          final database = RestDatabase(
            client: MockClient((request) async {
              sent.add(request.method);
              return _read('v');
            }),
            databaseUrl: 'https://example.invalid',
          );
          database.writes.fence = () => throw UnavailableError('closed');
          await expectLater(
            database.ref('/Slot').atomicUpdate((current) => 'w'),
            throwsA(isA<UnavailableError>()),
          );
          expect(sent, ['GET'], reason: 'it read, but never wrote');
        },
      );

      test('is not asked about reads', () async {
        final database = RestDatabase(
          client: MockClient((request) async => http.Response('1', 200)),
          databaseUrl: 'https://example.invalid',
        );
        database.writes.fence = () => throw UnavailableError('closed');
        expect((await database.ref('/Slot').once()).value, 1);
      });
    });

    test('children of a reference share the ledger and the timeout', () async {
      final release = Completer<http.Response>();
      final database = RestDatabase(
        client: MockClient((request) => release.future),
        databaseUrl: 'https://example.invalid',
        requestTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        database.ref('/A').child('b').remove(),
        throwsA(isA<UnavailableError>()),
      );
      expect(database.writes.pendingCount, 1);
      release.complete(http.Response('null', 200));
    });
  });
}
