import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_cli.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:test/test.dart';

import '../support/fake_mode_store.dart';

typedef _Result = ({int code, String out, String err});

void main() {
  late FakeModeStore store;
  var now = 5000000;
  String? project;

  setUp(() {
    store = FakeModeStore(
      config: const ServerModeConfig(mode: IdentityMode.coexist),
    );
    now = 5000000;
    project = null;
  });

  /// Runs the tool. Unless [bare], the project is named, as anything that
  /// changes data must.
  Future<_Result> run(List<String> args, {bool bare = false}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runModeCli(
      bare || args.contains('--project')
          ? args
          : [...args, '--project', 'demo-x'],
      storeFor: (p) {
        project = p;
        return store;
      },
      out: out,
      err: err,
      nowMs: () => now,
      sleep: (d) async => now += d.inMilliseconds,
    );
    return (code: code, out: out.toString(), err: err.toString());
  }

  InflightMarker marker(String id, {int ageSeconds = 5}) => InflightMarker(
    operationId: id,
    callable: 'link-or-create-tipper',
    startedAtMs: now - ageSeconds * 1000,
  );

  group('status', () {
    test('shows the mode and that nothing is in flight', () async {
      final result = await run(['status']);
      expect(result.code, 0);
      expect(result.out, contains('mode: coexist'));
      expect(result.out, contains('in flight: none'));
    });

    test(
      'lists each request with its age, and flags the overdue ones',
      () async {
        store.markers.addAll([
          marker('fresh', ageSeconds: 10),
          marker('old', ageSeconds: 600),
        ]);
        final result = await run(['status']);
        expect(
          result.out,
          contains('fresh  link-or-create-tipper  10s  running'),
        );
        expect(result.out, contains('old  link-or-create-tipper  600s  STALE'));
      },
    );

    test(
      'names the production project by default and takes --project',
      () async {
        await run(['status'], bare: true);
        expect(project, defaultModeToolProject);
        await run(['status', '--project', 'demo-x']);
        expect(project, 'demo-x');
      },
    );
  });

  group('set', () {
    test('without --yes only says what it would do', () async {
      final result = await run(['set', 'freeze']);
      expect(result.code, 0);
      expect(result.out, contains('coexist -> freeze'));
      expect(result.out, contains('Re-run with --yes'));
      expect(store.updates, isEmpty);
    });

    test(
      'with --yes switches the mode and, for a mode that forbids things, drains',
      () async {
        final result = await run([
          'set',
          'freeze',
          '--yes',
          '--project',
          'demo-x',
        ]);
        expect(result.code, 0, reason: result.out + result.err);
        expect(store.config.mode, IdentityMode.freeze);
        expect(
          result.out,
          contains('Quiet: no admitted request is still running.'),
        );
      },
    );

    test('a mode that only allows things does not wait', () async {
      final result = await run([
        'set',
        'coexist',
        '--yes',
        '--project',
        'demo-x',
      ]);
      expect(result.code, 0);
      expect(result.out, isNot(contains('Waiting for running requests')));
    });

    test(
      'switching to freeze with a request still running waits, then is not quiet',
      () async {
        store.markers.add(marker('busy', ageSeconds: 1));
        final result = await run([
          'set',
          'freeze',
          '--yes',
          '--max-wait-s',
          '6',
        ]);
        expect(result.code, 1);
        expect(result.out, contains('STILL RUNNING: busy'));
        expect(result.out, contains('NOT QUIET'));
        expect(
          store.config.mode,
          IdentityMode.freeze,
          reason: 'the mode change itself took effect',
        );
      },
    );

    test(
      'a stale marker blocks, with the way to check it and to clear it',
      () async {
        store.markers.add(marker('ghost', ageSeconds: 600));
        final result = await run([
          'set',
          'off',
          '--yes',
          '--project',
          'demo-x',
        ]);
        expect(result.code, 1);
        expect(result.out, contains('STALE, INVESTIGATE: ghost'));
        expect(result.out, contains('op=ghost'));
        expect(result.out, contains('--ack-stale ghost'));
        expect(store.removed, isEmpty);
      },
    );

    test('--no-drain skips the wait and says so', () async {
      store.markers.add(marker('busy', ageSeconds: 1));
      final result = await run([
        'set',
        'off',
        '--yes',
        '--no-drain',
        '--project',
        'demo-x',
      ]);
      expect(result.code, 0);
      expect(result.out, contains('may still be running'));
    });

    test('pilot needs users, and an unknown mode is refused', () async {
      final noPilots = await run([
        'set',
        'pilot',
        '--yes',
        '--project',
        'demo-x',
      ]);
      expect(noPilots.code, 2);
      expect(noPilots.err, contains('pilot'));
      final unknown = await run([
        'set',
        'banana',
        '--yes',
        '--project',
        'demo-x',
      ]);
      expect(unknown.code, 2);
      expect(unknown.err, contains('Unknown mode'));
      final pilot = await run([
        'set',
        'pilot',
        '--pilot-uids',
        'a, b',
        '--yes',
      ]);
      expect(pilot.code, 0, reason: pilot.err);
      expect(store.config.pilotUids, {'a', 'b'});
    });
  });

  group('drain', () {
    test('acknowledging a stale marker clears it', () async {
      store.markers.add(marker('ghost', ageSeconds: 600));
      final result = await run([
        'drain',
        '--ack-stale',
        'ghost',
        '--project',
        'demo-x',
      ]);
      expect(result.code, 0, reason: result.out);
      expect(result.out, contains('Cleared stale marker ghost'));
      expect(store.removed, ['ghost']);
    });

    test('acknowledging a marker that is still running is refused', () async {
      store.markers.add(marker('busy', ageSeconds: 3));
      final result = await run([
        'drain',
        '--ack-stale',
        'busy',
        '--max-wait-s',
        '2',
      ]);
      expect(result.code, 1);
      expect(result.out, contains('Not cleared: busy'));
      expect(store.removed, isEmpty);
    });
  });

  group('usage', () {
    test(
      'no command, an unknown command or option, and a bad wait are usage errors',
      () async {
        for (final args in [
          <String>[],
          ['frobnicate'],
          ['status', '--bogus'],
          ['set'],
          ['drain', '--max-wait-s', 'soon'],
          ['drain', '--ack-stale'],
        ]) {
          expect((await run(args)).code, 2, reason: '$args');
        }
      },
    );
  });
  group('naming the project', () {
    test(
      'anything that changes data must name the project, and nothing is touched without it',
      () async {
        store.markers.add(marker('ghost', ageSeconds: 600));
        for (final args in [
          ['set', 'freeze', '--yes'],
          ['drain', '--ack-stale', 'ghost'],
          ['set', 'off', '--yes', '--ack-stale', 'ghost'],
        ]) {
          final result = await run(args, bare: true);
          expect(result.code, 2, reason: '$args');
          expect(
            result.err,
            contains('the project must be named'),
            reason: '$args',
          );
        }
        expect(store.updates, isEmpty);
        expect(store.removed, isEmpty);
        expect(project, isNull, reason: 'no store was even opened');
      },
    );

    test(
      'reading needs no project: status, a dry-run set and a drain without --ack-stale use the default',
      () async {
        for (final args in [
          ['status'],
          ['set', 'freeze'],
          ['drain', '--max-wait-s', '0'],
        ]) {
          project = null;
          await run(args, bare: true);
          expect(project, defaultModeToolProject, reason: '$args');
        }
        expect(store.updates, isEmpty);
      },
    );
  });

  test(
    'corrupt in-flight data stops the command with an error instead of saying quiet',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runModeCli(
        ['drain'],
        storeFor: (_) => _CorruptStore(),
        out: out,
        err: err,
      );
      expect(code, 1);
      expect(err.toString(), contains('not a set of markers'));
      expect(out.toString(), isNot(contains('Quiet')));
    },
  );
}

/// A store whose in-flight node is corrupt.
class _CorruptStore extends FakeModeStore {
  @override
  Future<List<InflightMarker>> readInflight() async =>
      parseInflight('corrupted');
}
