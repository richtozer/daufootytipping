import 'dart:convert';

import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/identity_records_store.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/purge_cli.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:test/test.dart';

/// The two nodes, held in memory, applying a patch the way the database does.
class _MemoryStore implements IdentityRecordsStore {
  _MemoryStore(this.tippers, this.privateRecords, this.events);

  Map<String, Object?> tippers;
  Map<String, Object?> privateRecords;
  final List<String> events;
  final List<Map<String, Object?>> applied = <Map<String, Object?>>[];

  /// Called on every read of the public node, to let a test change the data
  /// between two reads.
  void Function(int read)? onRead;
  int reads = 0;

  /// Set to make the write a no-op, to show the verification catches it.
  bool dropWrites = false;

  @override
  Future<Object?> readTippers() async {
    reads += 1;
    onRead?.call(reads);
    return jsonDecode(jsonEncode(tippers));
  }

  @override
  Future<Object?> readTipperPrivate() async =>
      jsonDecode(jsonEncode(privateRecords));

  @override
  Future<void> applyPatch(Map<String, Object?> patch) async {
    events.add('patch applied');
    applied.add(patch);
    if (dropWrites) {
      return;
    }
    for (final entry in patch.entries) {
      final parts = entry.key.split('/');
      final node = parts[0] == 'AllTippers' ? tippers : privateRecords;
      final record = node[parts[1]]! as Map<String, Object?>;
      if (entry.value == null) {
        record.remove(parts[2]);
      } else {
        record[parts[2]] = entry.value;
      }
    }
  }
}

class _FakeModes implements ModeStore {
  _FakeModes(this.mode, [this.inflight = const <InflightMarker>[]]);

  final IdentityMode mode;
  final List<InflightMarker> inflight;

  @override
  Future<ServerModeConfig> readMode() async => ServerModeConfig(mode: mode);

  @override
  Future<List<InflightMarker>> readInflight() async => inflight;

  @override
  Future<void> updateIdentityNode(Map<String, Object?> fields) async =>
      throw StateError('the purge must not change the mode');

  @override
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry) async =>
      throw StateError('the purge must not change the mode');

  @override
  Future<void> removeMarker(String operationId) async =>
      throw StateError('the purge must not clear a marker');
}

Map<String, Object?> _publicRecord(String name, String email) =>
    <String, Object?>{
      'name': name,
      'photoURL': '$name.png',
      'authuid': 'uid-$name',
      'tipperRole': 'tipper',
      'email': email,
      'logon': email,
      'isAnonymous': false,
      'acctCreatedUTC': '2025-01-01T00:00:00.000Z',
      'acctLoggedOnUTC': '2026-10-01T00:00:00.000Z',
    };

Map<String, Object?> _privateRecord(
  String name,
  String email,
) => <String, Object?>{
  for (final entry in _publicRecord(name, email).entries)
    if (entry.key != 'name' && entry.key != 'photoURL') entry.key: entry.value,
};

_MemoryStore _unpurged(List<String> events) => _MemoryStore(
  <String, Object?>{
    't1': _publicRecord('alice', 'alice.secret@example.test'),
    't2': _publicRecord('bob', 'bob.secret@example.test'),
  },
  <String, Object?>{
    't1': _privateRecord('alice', 'alice.secret@example.test'),
    't2': _privateRecord('bob', 'bob.secret@example.test'),
  },
  events,
);

class _Run {
  _Run(this.code, this.out, this.err, this.files);

  final int code;
  final String out;
  final String err;

  /// What was written to files, by path.
  final Map<String, String> files;
}

Future<_Run> _run(
  List<String> arguments,
  _MemoryStore store, {
  IdentityMode mode = IdentityMode.freeze,
  List<InflightMarker> inflight = const <InflightMarker>[],
  Set<String> existing = const <String>{},
  bool failWrites = false,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final files = <String, String>{};
  final code = await runPurgeCli(
    arguments,
    storeFor: (_) => store,
    modeFor: (_) => _FakeModes(mode, inflight),
    out: out,
    err: err,
    writeFile: (path, contents) async {
      if (failWrites) {
        throw StateError('disk full');
      }
      store.events.add('file written: $path');
      files[path] = contents;
    },
    fileExists: existing.contains,
  );
  return _Run(code, '$out', '$err', files);
}

void main() {
  late List<String> events;
  late _MemoryStore store;

  setUp(() {
    events = <String>[];
    store = _unpurged(events);
  });

  group('without --apply', () {
    test(
      'it only plans: it says what it would do and writes nothing',
      () async {
        final run = await _run(<String>[], store);

        expect(run.code, 0, reason: run.err);
        expect(run.out, contains('Would remove 14 field(s) from 2 record(s)'));
        expect(run.out, contains('Plan only'));
        expect(store.applied, isEmpty);
        expect(run.files, isEmpty);
      },
    );

    test('--out saves the patch, which holds no email address', () async {
      final run = await _run(<String>['--out', 'patch.json'], store);

      expect(run.files.keys, ['patch.json']);
      expect(run.files['patch.json'], isNot(contains('example.test')));
      expect(store.applied, isEmpty);
    });

    test(
      'a later public login time is reported as written to the private record',
      () async {
        (store.tippers['t1']! as Map)['acctLoggedOnUTC'] =
            '2026-11-05T00:00:00.000Z';

        final run = await _run(<String>[], store);

        expect(run.out, contains('1 later login time(s)'));
      },
    );
  });

  group('usage', () {
    test('--apply needs the project named', () async {
      final run = await _run(<String>[
        '--apply',
        '--snapshot',
        's.json',
      ], store);

      expect(run.code, 2);
      expect(run.err, contains('the project must be named'));
      expect(store.applied, isEmpty);
    });

    test('--apply needs a snapshot file', () async {
      final run = await _run(<String>['--apply', '--project', 'p'], store);

      expect(run.code, 2);
      expect(run.err, contains('--snapshot'));
      expect(store.applied, isEmpty);
    });

    test('an unknown option is a usage error', () async {
      expect((await _run(<String>['--frobnicate'], store)).code, 2);
    });
  });

  group('--apply', () {
    const apply = <String>[
      '--apply',
      '--project',
      'p',
      '--snapshot',
      'snap.json',
    ];

    test(
      'saves the public records first, then writes one patch, then verifies',
      () async {
        final before = jsonEncode(store.tippers);

        final run = await _run(apply, store);

        expect(run.code, 0, reason: run.err);
        expect(events, ['file written: snap.json', 'patch applied']);
        expect(
          run.files['snap.json'],
          before,
          reason: 'the snapshot is the state before',
        );
        expect(store.applied, hasLength(1));
        expect(run.out, contains('a second plan finds nothing left'));
        expect(run.out, contains('set the identity mode to final'));
        expect(store.tippers['t1'], {'name': 'alice', 'photoURL': 'alice.png'});
        expect(
          (store.privateRecords['t1']! as Map)['email'],
          'alice.secret@example.test',
        );
      },
    );

    test('keeps a later public login time in the private record', () async {
      (store.tippers['t1']! as Map)['acctLoggedOnUTC'] =
          '2026-11-05T00:00:00.000Z';

      await _run(apply, store);

      expect(
        (store.privateRecords['t1']! as Map)['acctLoggedOnUTC'],
        '2026-11-05T00:00:00.000Z',
      );
    });

    test(
      'run again, it finds nothing to do and needs no new snapshot',
      () async {
        await _run(apply, store);
        final again = await _run(apply, store, existing: {'snap.json'});

        expect(again.code, 0);
        expect(again.out, contains('Nothing to purge'));
        expect(store.applied, hasLength(1));
      },
    );

    test('says nothing a person could be identified by', () async {
      final run = await _run(apply, store);

      expect(run.out + run.err, isNot(contains('example.test')));
      expect(run.out + run.err, isNot(contains('uid-')));
    });

    test('runs with the identity mode off too', () async {
      final run = await _run(apply, store, mode: IdentityMode.off);

      expect(run.code, 0, reason: run.err);
    });

    group('refuses, writing nothing and saving nothing, when', () {
      void expectUntouched(_Run run) {
        expect(run.code, 1);
        expect(store.applied, isEmpty);
        expect(run.files, isEmpty);
      }

      for (final mode in [
        IdentityMode.coexist,
        IdentityMode.finalShape,
        IdentityMode.pilot,
      ]) {
        test('the identity mode is ${mode.name}', () async {
          final run = await _run(apply, store, mode: mode);

          expectUntouched(run);
          expect(run.err, contains('Set freeze'));
        });
      }

      test('a request is still in flight', () async {
        final run = await _run(
          apply,
          store,
          inflight: const [InflightMarker(operationId: 'op-1')],
        );

        expectUntouched(run);
        expect(run.err, contains('still in flight'));
      });

      test('the snapshot file already exists', () async {
        final run = await _run(apply, store, existing: {'snap.json'});

        expectUntouched(run);
        expect(run.err, contains('never overwritten'));
      });

      test('the data changes between the two reads', () async {
        store.onRead = (read) {
          if (read == 2) {
            (store.tippers['t2']! as Map)['acctLoggedOnUTC'] =
                '2026-12-01T00:00:00.000Z';
          }
        };

        final run = await _run(apply, store);

        expectUntouched(run);
        expect(run.err, contains('data changed'));
      });

      test('the snapshot cannot be saved', () async {
        final run = await _run(apply, store, failWrites: true);

        expect(run.code, 1);
        expect(store.applied, isEmpty);
        expect(run.err, contains('could not save the snapshot'));
      });
    });

    test('a write that did not take is reported, not claimed', () async {
      store.dropWrites = true;

      final run = await _run(apply, store);

      expect(run.code, 1);
      expect(run.err, contains('NOT VERIFIED'));
    });
  });

  group('an unresolved tipper', () {
    test(
      'blocks the whole run, naming the opaque id and field, never a value',
      () async {
        store.privateRecords.remove('t1');

        final run = await _run(const [
          '--apply',
          '--project',
          'p',
          '--snapshot',
          'snap.json',
        ], store);

        expect(run.code, 1);
        expect(run.err, contains('BLOCKED'));
        expect(
          run.err,
          contains(
            't1: has identity fields in its public record but no private record',
          ),
        );
        expect(run.err, isNot(contains('example.test')));
        expect(store.applied, isEmpty);
        expect(run.files, isEmpty);
        expect(
          (store.tippers['t2']! as Map).containsKey('email'),
          isTrue,
          reason: 'the resolved tipper is not purged on its own',
        );
      },
    );

    test('a field that differs is named', () async {
      (store.privateRecords['t2']! as Map)['email'] = 'changed@example.test';

      final run = await _run(<String>[], store);

      expect(run.code, 1);
      expect(run.err, contains('t2: email differs'));
      expect(run.err, isNot(contains('example.test')));
    });
  });
}
