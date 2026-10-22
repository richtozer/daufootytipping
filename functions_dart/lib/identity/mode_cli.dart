import 'dart:async';

import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/server_mode.dart';

/// The Firebase project the owner's tool targets unless told otherwise.
const String defaultModeToolProject = 'dau-footy-tipping-f8a42';

const String modeToolUsage =
    '''
Shows or changes the identity server mode (DESIGN-database-rules-phase4.md, section 5) and waits for running
requests to finish. It talks to the database through the Firebase CLI you are logged into.

Usage: dart run bin/identity_mode.dart <command> [options]

  status                          the mode, the pilot users and every request in flight
  set <mode> [options]            off | pilot | coexist | freeze | final. Shows what it would do; add --yes to do it.
      --pilot-uids a,b            the pilot users (required for the first switch to pilot)
      --yes                       actually change the mode
      --no-drain                  do not wait for running requests afterwards
  drain [options]                 wait until no admitted request is still running

Options for set and drain:
  --max-wait-s <n>                how long to wait for running requests (default 300)
  --ack-stale <id,id>             clear stale markers you have checked in the logs (see below)

  --project <id>                  default $defaultModeToolProject

A marker is "stale" when its request is overdue (older than its 60 second timeout plus 30 seconds). Overdue does
not mean finished: a timed-out request can keep running. The drain never deletes a marker on age and never
reports quiet while one remains. To clear one, check the logs for its operation id (an "end" line means it
finished) and name it in --ack-stale. A marker still within its timeout cannot be acknowledged.
Exit codes: 0 quiet or done, 1 not quiet, 2 usage.
''';

/// Runs the mode tool. [storeFor] builds the store for a project, so tests can
/// supply one over the emulator.
Future<int> runModeCli(
  List<String> arguments, {
  required ModeStore Function(String project) storeFor,
  required StringSink out,
  required StringSink err,
  int Function()? nowMs,
  Future<void> Function(Duration)? sleep,
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final wait = sleep ?? (Duration d) => Future<void>.delayed(d);

  final _Parsed parsed;
  try {
    parsed = _Parsed.parse(arguments);
  } on FormatException catch (error) {
    err.writeln('${error.message}\n\n$modeToolUsage');
    return 2;
  }
  final store = storeFor(parsed.project);

  try {
    switch (parsed.command) {
      case 'status':
        await _status(store, clock, out);
        return 0;
      case 'drain':
        return await _drain(store, parsed, clock, wait, out);
      case 'set':
        return await _set(store, parsed, clock, wait, out, err);
    }
  } on ArgumentError catch (error) {
    err.writeln('ERROR: ${error.message}');
    return 2;
  } on StateError catch (error) {
    err.writeln('ERROR: ${error.message}');
    return 1;
  }
  return 2;
}

Future<void> _status(
  ModeStore store,
  int Function() clock,
  StringSink out,
) async {
  final config = await store.readMode();
  final markers = await store.readInflight();
  out.writeln('mode: ${config.mode.wire}');
  if (config.mode == IdentityMode.pilot) {
    out.writeln('pilot users: ${config.pilotUids.length}');
  }
  if (markers.isEmpty) {
    out.writeln('in flight: none');
    return;
  }
  out.writeln('in flight: ${markers.length}');
  const staleAfter = staleMarkerAfter;
  for (final marker in markers) {
    final started = marker.startedAtMs;
    final age = started == null
        ? 'unknown age'
        : '${((clock() - started) / 1000).round()}s';
    final flag = marker.isStale(clock(), staleAfter) ? 'STALE' : 'running';
    out.writeln(
      '  ${marker.operationId}  ${marker.callable ?? '?'}  $age  $flag',
    );
  }
}

Future<int> _drain(
  ModeStore store,
  _Parsed parsed,
  int Function() clock,
  Future<void> Function(Duration) wait,
  StringSink out,
) async {
  out.writeln('Waiting for running requests to finish...');
  final result = await drainInflight(
    store,
    nowMs: clock,
    sleep: wait,
    maxWait: Duration(seconds: parsed.maxWaitSeconds),
    acknowledge: parsed.acknowledge,
  );
  for (final id in result.acknowledged) {
    out.writeln('Cleared stale marker $id (acknowledged).');
  }
  for (final id in result.refusedAcknowledgements) {
    out.writeln(
      'Not cleared: $id is not a stale marker (still within its timeout, or already gone).',
    );
  }
  if (result.quiet) {
    out.writeln('Quiet: no admitted request is still running.');
    return 0;
  }
  for (final marker in result.stillRunning) {
    out.writeln(
      'STILL RUNNING: ${marker.operationId} (${marker.callable ?? '?'}). Run drain again shortly.',
    );
  }
  for (final marker in result.stale) {
    out.writeln(
      'STALE, INVESTIGATE: ${marker.operationId} (${marker.callable ?? '?'}). Its request is overdue, which does not mean it has '
      'ended. Look for its "end" line:  gcloud logging read \'textPayload:"op=${marker.operationId}"\'. '
      'Then clear it with --ack-stale ${marker.operationId}.',
    );
  }
  out.writeln(
    'NOT QUIET: do not proceed with anything that needs the system quiet.',
  );
  return 1;
}

Future<int> _set(
  ModeStore store,
  _Parsed parsed,
  int Function() clock,
  Future<void> Function(Duration) wait,
  StringSink out,
  StringSink err,
) async {
  final mode = IdentityMode.fromWire(parsed.modeArgument);
  if (mode == null) {
    err.writeln(
      'Unknown mode "${parsed.modeArgument}". Use off, pilot, coexist, freeze or final.',
    );
    return 2;
  }
  final current = await store.readMode();
  out.writeln(
    'Mode ${current.mode.wire} -> ${mode.wire}'
    '${parsed.pilotUids == null ? '' : ' (pilot users: ${parsed.pilotUids!.length})'}.',
  );
  if (!parsed.yes) {
    out.writeln('Not changed. Re-run with --yes to change it.');
    return 0;
  }
  await setIdentityMode(
    store,
    mode: mode,
    pilotUids: parsed.pilotUids,
    nowMs: clock(),
  );
  out.writeln('Mode is now ${mode.wire}. New requests follow it at once.');
  if (!mode.needsDrain || parsed.noDrain) {
    if (mode.needsDrain) {
      out.writeln(
        'Not waiting for running requests (--no-drain): they may still be running.',
      );
    }
    return 0;
  }
  return _drain(store, parsed, clock, wait, out);
}

class _Parsed {
  _Parsed({
    required this.command,
    required this.project,
    required this.modeArgument,
    required this.pilotUids,
    required this.yes,
    required this.noDrain,
    required this.maxWaitSeconds,
    required this.acknowledge,
  });

  final String command;
  final String project;
  final String? modeArgument;
  final Set<String>? pilotUids;
  final bool yes;
  final bool noDrain;
  final int maxWaitSeconds;
  final Set<String> acknowledge;

  static _Parsed parse(List<String> arguments) {
    if (arguments.isEmpty || arguments.first == '--help') {
      throw const FormatException('A command is required.');
    }
    final command = arguments.first;
    if (!{'status', 'set', 'drain'}.contains(command)) {
      throw FormatException('Unknown command: $command');
    }
    var index = 1;
    String? modeArgument;
    if (command == 'set') {
      if (arguments.length < 2 || arguments[1].startsWith('--')) {
        throw const FormatException('set needs a mode.');
      }
      modeArgument = arguments[1];
      index = 2;
    }
    final values = <String, String>{};
    final flags = <String>{};
    for (; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if ({
        '--pilot-uids',
        '--max-wait-s',
        '--ack-stale',
        '--project',
      }.contains(argument)) {
        if (index + 1 >= arguments.length) {
          throw FormatException('$argument needs a value.');
        }
        values[argument] = arguments[index += 1];
      } else if (argument == '--yes' || argument == '--no-drain') {
        flags.add(argument);
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }
    final maxWait = int.tryParse(values['--max-wait-s'] ?? '300');
    if (maxWait == null || maxWait < 0) {
      throw const FormatException('--max-wait-s must be a number of seconds.');
    }
    Set<String> list(String? raw) => {
      for (final part in (raw ?? '').split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
    return _Parsed(
      command: command,
      project: values['--project'] ?? defaultModeToolProject,
      modeArgument: modeArgument,
      pilotUids: values.containsKey('--pilot-uids')
          ? list(values['--pilot-uids'])
          : null,
      yes: flags.contains('--yes'),
      noDrain: flags.contains('--no-drain'),
      maxWaitSeconds: maxWait,
      acknowledge: list(values['--ack-stale']),
    );
  }
}
