import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/restore_cli.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:test/test.dart';

/// The two nodes, held in memory, applying a patch the way the database does.
class _MemoryStore implements RestoreStore {
  _MemoryStore(this.tippers, this.privateRecords);

  Map<String, Object?> tippers;
  Map<String, Object?> privateRecords;
  final List<Map<String, Object?>> applied = <Map<String, Object?>>[];

  /// Called on every read, to let a test change the data between two reads.
  void Function(int read)? onRead;
  int reads = 0;

  @override
  Future<Object?> readTippers() async {
    reads += 1;
    onRead?.call(reads);
    return jsonDecode(jsonEncode(tippers));
  }

  @override
  Future<Object?> readTipperPrivate() async =>
      jsonDecode(jsonEncode(privateRecords));

  /// Set to make the write a no-op, to show the verification catches it.
  bool dropWrites = false;

  @override
  Future<void> applyPatch(Map<String, Object?> patch) async {
    applied.add(patch);
    if (dropWrites) {
      return;
    }
    for (final entry in patch.entries) {
      final parts = entry.key.split('/');
      (tippers[parts[1]]! as Map<String, Object?>)[parts[2]] = entry.value;
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
      throw StateError('the restore must not change the mode');

  @override
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry) async =>
      throw StateError('the restore must not change the mode');

  @override
  Future<void> removeMarker(String operationId) async =>
      throw StateError('the restore must not clear a marker');
}

_MemoryStore _purged() => _MemoryStore(
  <String, Object?>{
    't1': <String, Object?>{'name': 'Alice', 'photoURL': 'a.png'},
    't2': <String, Object?>{'name': 'Bob'},
  },
  <String, Object?>{
    't1': <String, Object?>{
      'authuid': 'uidA',
      'tipperRole': 'admin',
      'email': 'alice.secret@example.test',
      'logon': 'alice.secret@example.test',
    },
    't2': <String, Object?>{
      'authuid': 'uidB',
      'tipperRole': 'tipper',
      'email': 'bob.secret@example.test',
    },
  },
);

class _Run {
  _Run(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;
}

Future<_Run> _run(
  List<String> arguments,
  _MemoryStore store, {
  IdentityMode mode = IdentityMode.freeze,
  List<InflightMarker> inflight = const <InflightMarker>[],
  Future<void> Function(String, String)? writeFile,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runRestoreCli(
    arguments,
    storeFor: (_) => store,
    modeFor: (_) => _FakeModes(mode, inflight),
    out: out,
    err: err,
    writeFile: writeFile,
  );
  return _Run(code, '$out', '$err');
}

void main() {
  group('the restore tool', () {
    test(
      'by default it only plans: it says what it would do and writes nothing',
      () async {
        final store = _purged();
        final run = await _run(<String>[], store);
        expect(run.code, 0);
        expect(
          run.out,
          contains(
            'Would restore 7 field(s) on 2 record(s)'.replaceFirst(
              '7',
              '${_count(store)}',
            ),
          ),
        );
        expect(run.out, contains('Plan only'));
        expect(store.applied, isEmpty);
      },
    );

    test('--apply needs the project named', () async {
      final store = _purged();
      final run = await _run(<String>['--apply'], store);
      expect(run.code, 2);
      expect(run.err, contains('the project must be named'));
      expect(store.applied, isEmpty);
    });

    test('an unknown option is a usage error', () async {
      final run = await _run(<String>['--frobnicate'], _purged());
      expect(run.code, 2);
    });

    test(
      '--apply writes one patch, then verifies that nothing is left to restore',
      () async {
        final store = _purged();
        final run = await _run(<String>['--apply', '--project', 'p'], store);
        expect(run.code, 0, reason: run.err);
        expect(store.applied, hasLength(1));
        expect(run.out, contains('a second plan finds nothing left'));
        expect(run.out, contains('deploy R1-compat'));
        expect((store.tippers['t1']! as Map)['tipperRole'], 'admin');
        expect((store.tippers['t2']! as Map)['authuid'], 'uidB');

        final again = await _run(<String>['--apply', '--project', 'p'], store);
        expect(again.code, 0);
        expect(again.out, contains('Nothing to restore'));
        expect(
          store.applied,
          hasLength(1),
          reason: 'a second run writes nothing',
        );
      },
    );

    for (final mode in <IdentityMode>[
      IdentityMode.coexist,
      IdentityMode.finalShape,
      IdentityMode.pilot,
    ]) {
      test('--apply refuses while the identity mode is ${mode.name}', () async {
        final store = _purged();
        final run = await _run(
          <String>['--apply', '--project', 'p'],
          store,
          mode: mode,
        );
        expect(run.code, 1);
        expect(run.err, contains('Set freeze (or off) and drain first'));
        expect(store.applied, isEmpty);
      });
    }

    test('--apply is allowed under off as well as freeze', () async {
      final store = _purged();
      expect(
        (await _run(
          <String>['--apply', '--project', 'p'],
          store,
          mode: IdentityMode.off,
        )).code,
        0,
      );
    });

    test('--apply refuses while a request is still in flight', () async {
      final store = _purged();
      final run = await _run(
        <String>['--apply', '--project', 'p'],
        store,
        inflight: const <InflightMarker>[InflightMarker(operationId: 'op1')],
      );
      expect(run.code, 1);
      expect(run.err, contains('still in flight'));
      expect(store.applied, isEmpty);
    });

    test('a blocked plan writes nothing and names only opaque ids', () async {
      final store = _purged()..tippers.remove('t2');
      final run = await _run(<String>['--apply', '--project', 'p'], store);
      expect(run.code, 1);
      expect(run.err, contains('BLOCKED'));
      expect(run.err, contains('t2'));
      expect(store.applied, isEmpty);
    });

    test(
      'data that changes between the two reads stops it before anything is written',
      () async {
        final store = _purged();
        // The first plan is made from reads 1; the stability re-read is read 2.
        store.onRead = (read) {
          if (read == 2) {
            (store.tippers['t1']! as Map<String, Object?>)['authuid'] =
                'uidChanged';
          }
        };
        final run = await _run(<String>['--apply', '--project', 'p'], store);
        expect(run.code, 1);
        expect(run.err, contains('changed between the two reads'));
        expect(store.applied, isEmpty);
      },
    );

    test('a write that did not take is reported, not claimed', () async {
      final store = _purged()..dropWrites = true;
      final run = await _run(<String>['--apply', '--project', 'p'], store);
      expect(run.code, 1);
      expect(run.err, contains('NOT VERIFIED'));
    });

    test(
      '--out writes the patch to the file named, and says it holds email addresses',
      () async {
        final store = _purged();
        String? path;
        String? contents;
        final run = await _run(
          <String>['--out', 'patch.json'],
          store,
          writeFile: (p, c) async {
            path = p;
            contents = c;
          },
        );
        expect(run.code, 0);
        expect(path, 'patch.json');
        expect(jsonDecode(contents!), isA<Map>());
        expect(run.out, contains('holds email addresses'));
      },
    );

    test(
      'nothing it prints names an email address, an account id or a value',
      () async {
        final store = _purged();
        final run = await _run(<String>['--apply', '--project', 'p'], store);
        final all = '${run.out}${run.err}';
        for (final secret in <String>[
          'secret',
          'example.test',
          'uidA',
          'uidB',
          'Alice',
          'Bob',
        ]) {
          expect(all, isNot(contains(secret)));
        }
      },
    );
  });

  group('the Firebase CLI store', () {
    test(
      'reads the two nodes and writes one update from a file, with triggers suppressed',
      () async {
        final calls = <List<String>>[];
        String? fileContents;
        Future<ProcessResult> runner(
          String executable,
          List<String> arguments,
        ) async {
          calls.add(arguments);
          if (arguments.first == 'database:update') {
            fileContents = await File(arguments[2]).readAsString();
          }
          return ProcessResult(
            0,
            0,
            arguments.first == 'database:get' ? '{"a":1}' : '',
            '',
          );
        }

        final store = CliRestoreStore(project: 'proj', runner: runner);
        expect(await store.readTippers(), <String, Object?>{'a': 1});
        expect(await store.readTipperPrivate(), <String, Object?>{'a': 1});
        await store.applyPatch(<String, Object?>{
          'AllTippers/t1/authuid': 'uidA',
        });

        expect(calls[0], ['database:get', '/AllTippers', '--project', 'proj']);
        expect(calls[1], [
          'database:get',
          '/TipperPrivate',
          '--project',
          'proj',
        ]);
        expect(calls[2].sublist(0, 2), ['database:update', '/']);
        expect(
          calls[2],
          containsAll(['--force', '--disable-triggers', '--project', 'proj']),
        );
        expect(jsonDecode(fileContents!), <String, Object?>{
          'AllTippers/t1/authuid': 'uidA',
        });
        expect(
          File(calls[2][2]).existsSync(),
          false,
          reason: 'the patch file is deleted',
        );
      },
    );

    test('a failing command is an error that says which', () async {
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments,
      ) async => ProcessResult(0, 1, '', 'boom');
      final store = CliRestoreStore(project: 'proj', runner: runner);
      await expectLater(store.readTippers(), throwsA(isA<StateError>()));
    });

    test('an empty node reads as nothing', () async {
      Future<ProcessResult> runner(
        String executable,
        List<String> arguments,
      ) async => ProcessResult(0, 0, 'null\n', '');
      expect(
        await CliRestoreStore(project: 'p', runner: runner).readTippers(),
        isNull,
      );
    });
  });
}

int _count(_MemoryStore store) {
  var fields = 0;
  for (final entry in store.privateRecords.entries) {
    final privateRecord = entry.value! as Map;
    final publicRecord = store.tippers[entry.key]! as Map;
    fields += privateRecord.keys
        .where((k) => !publicRecord.containsKey(k))
        .length;
  }
  return fields;
}
