import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_cli.dart';
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

  Future<_Result> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runModeCli(
      args,
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
        await run(['status']);
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
        final result = await run(['set', 'freeze', '--yes']);
        expect(result.code, 0, reason: result.out + result.err);
        expect(store.config.mode, IdentityMode.freeze);
        expect(
          result.out,
          contains('Quiet: no admitted request is still running.'),
        );
      },
    );

    test('a mode that only allows things does not wait', () async {
      final result = await run(['set', 'coexist', '--yes']);
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
        final result = await run(['set', 'off', '--yes']);
        expect(result.code, 1);
        expect(result.out, contains('STALE, INVESTIGATE: ghost'));
        expect(result.out, contains('op=ghost'));
        expect(result.out, contains('--ack-stale ghost'));
        expect(store.removed, isEmpty);
      },
    );

    test('--no-drain skips the wait and says so', () async {
      store.markers.add(marker('busy', ageSeconds: 1));
      final result = await run(['set', 'off', '--yes', '--no-drain']);
      expect(result.code, 0);
      expect(result.out, contains('may still be running'));
    });

    test('pilot needs users, and an unknown mode is refused', () async {
      final noPilots = await run(['set', 'pilot', '--yes']);
      expect(noPilots.code, 2);
      expect(noPilots.err, contains('pilot'));
      final unknown = await run(['set', 'banana', '--yes']);
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
      final result = await run(['drain', '--ack-stale', 'ghost']);
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
}
