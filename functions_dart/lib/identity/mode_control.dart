import 'dart:convert';
import 'dart:io';

import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';

/// The identity mode node as the owner's tool sees it. Two implementations: one
/// over the REST handle (tests, against the emulator) and one over the Firebase
/// CLI the owner is already logged into (production, so no extra credentials).
abstract interface class ModeStore {
  /// The mode and pilot list as stored.
  Future<ServerModeConfig> readMode();

  /// Every in-flight marker.
  Future<List<InflightMarker>> readInflight();

  /// Merges [fields] into the identity node. Never replaces it, because that
  /// would erase the in-flight markers beneath it.
  Future<void> updateIdentityNode(Map<String, Object?> fields);

  /// Appends one entry to the mode-change log.
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry);

  /// Removes one marker.
  Future<void> removeMarker(String operationId);
}

/// A [ModeStore] over the REST handle.
class RestModeStore implements ModeStore {
  RestModeStore(this._database);

  final RestDatabase _database;

  @override
  Future<ServerModeConfig> readMode() => readServerMode(_database);

  @override
  Future<List<InflightMarker>> readInflight() async =>
      parseInflight((await _database.ref(inflightPath).once()).value);

  @override
  Future<void> updateIdentityNode(Map<String, Object?> fields) =>
      _database.ref(identityModePath).update(fields);

  @override
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry) =>
      _database.ref('$identityModeLogPath/$atMs').set(entry);

  @override
  Future<void> removeMarker(String operationId) =>
      _database.ref('$inflightPath/$operationId').remove();
}

/// Runs an executable and returns its result. A parameter so a test can stand
/// in for the `firebase` command.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// A [ModeStore] over the Firebase CLI, for the owner to run against production.
class CliModeStore implements ModeStore {
  CliModeStore({
    required this.project,
    this.executable = 'firebase',
    ProcessRunner? runner,
  }) : _run = runner ?? Process.run;

  final String project;
  final String executable;
  final ProcessRunner _run;

  Future<String> _firebase(List<String> arguments) async {
    final result = await _run(executable, [...arguments, '--project', project]);
    if (result.exitCode != 0) {
      throw StateError(
        'firebase ${arguments.first} failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    return '${result.stdout}';
  }

  Object? _decode(String output) {
    final text = output.trim();
    return text.isEmpty ? null : jsonDecode(text);
  }

  @override
  Future<ServerModeConfig> readMode() async {
    final node = _decode(await _firebase(['database:get', identityModePath]));
    if (node is! Map) {
      return const ServerModeConfig.off();
    }
    return ServerModeConfig.parse(
      mode: node['mode'],
      pilotUids: node['pilotUids'],
    );
  }

  @override
  Future<List<InflightMarker>> readInflight() async =>
      parseInflight(_decode(await _firebase(['database:get', inflightPath])));

  @override
  Future<void> updateIdentityNode(Map<String, Object?> fields) async {
    await _firebase([
      'database:update',
      identityModePath,
      '--data',
      jsonEncode(fields),
      '--force',
    ]);
  }

  @override
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry) async {
    await _firebase([
      'database:update',
      identityModeLogPath,
      '--data',
      jsonEncode(<String, Object?>{'$atMs': entry}),
      '--force',
    ]);
  }

  @override
  Future<void> removeMarker(String operationId) async {
    await _firebase([
      'database:remove',
      '$inflightPath/$operationId',
      '--force',
    ]);
  }
}

/// Reads the stored markers, malformed ones included.
List<InflightMarker> parseInflight(Object? raw) {
  if (raw is! Map) {
    return const <InflightMarker>[];
  }
  return [
    for (final entry in raw.entries)
      InflightMarker.parse(entry.key.toString(), entry.value),
  ]..sort((a, b) => a.operationId.compareTo(b.operationId));
}

/// Switches the mode: merges the new values (never the whole node) and logs the
/// change. Returns the mode that was in force before.
Future<ServerModeConfig> setIdentityMode(
  ModeStore store, {
  required IdentityMode mode,
  Set<String>? pilotUids,
  required int nowMs,
  String changedBy = 'owner',
}) async {
  if (mode == IdentityMode.pilot &&
      (pilotUids == null || pilotUids.isEmpty) &&
      (await store.readMode()).pilotUids.isEmpty) {
    throw ArgumentError('pilot mode needs at least one pilot uid.');
  }
  final previous = await store.readMode();
  final fields = <String, Object?>{
    'mode': mode.wire,
    'changedAtMs': nowMs,
    'changedBy': changedBy,
    if (pilotUids != null) 'pilotUids': pilotUids.toList()..sort(),
  };
  await store.updateIdentityNode(fields);
  await store.appendModeLog(nowMs, <String, Object?>{
    'from': previous.mode.wire,
    'to': mode.wire,
    'changedBy': changedBy,
    if (pilotUids != null) 'pilotUids': pilotUids.toList()..sort(),
  });
  return previous;
}

/// The outcome of a drain.
class DrainResult {
  const DrainResult({
    required this.quiet,
    required this.stale,
    required this.stillRunning,
    required this.acknowledged,
    required this.refusedAcknowledgements,
  });

  /// No marker remains: nothing admitted is still running.
  final bool quiet;

  /// Markers overdue by more than the timeout and margin. Overdue is not dead:
  /// the request may still be running. They need investigating.
  final List<InflightMarker> stale;

  /// Markers that are not yet overdue (still within the timeout).
  final List<InflightMarker> stillRunning;

  /// Stale markers the owner explicitly acknowledged, now removed.
  final List<String> acknowledged;

  /// Acknowledgements refused because the marker was not stale (or not found).
  final List<String> refusedAcknowledgements;
}

/// Waits for every admitted request to finish (section 5, step 2).
///
/// It polls the in-flight markers. A marker is **never** removed on age alone,
/// and the system is never reported quiet while one remains: a timed-out Cloud
/// Run request can keep running, so an overdue marker is reported and the drain
/// stops waiting for it. It is removed only if the owner names it in
/// [acknowledge] after checking the logs, and only if it is overdue; a marker
/// still within its timeout cannot be acknowledged.
Future<DrainResult> drainInflight(
  ModeStore store, {
  required int Function() nowMs,
  required Future<void> Function(Duration) sleep,
  Duration pollInterval = const Duration(seconds: 2),
  Duration maxWait = const Duration(minutes: 5),
  Duration staleAfter = staleMarkerAfter,
  Set<String> acknowledge = const {},
}) async {
  final deadline = nowMs() + maxWait.inMilliseconds;
  final acknowledged = <String>[];
  final refused = <String>[];
  final pending = <String>{...acknowledge};

  while (true) {
    var markers = await store.readInflight();

    for (final id in pending.toList()) {
      final marker = markers.where((m) => m.operationId == id).firstOrNull;
      if (marker == null) {
        pending.remove(id);
        refused.add(id);
      } else if (marker.isStale(nowMs(), staleAfter)) {
        await store.removeMarker(id);
        acknowledged.add(id);
        pending.remove(id);
      } else {
        pending.remove(id);
        refused.add(id);
      }
    }
    if (acknowledged.isNotEmpty) {
      markers = await store.readInflight();
    }

    final stale = [
      for (final marker in markers)
        if (marker.isStale(nowMs(), staleAfter)) marker,
    ];
    final running = [
      for (final marker in markers)
        if (!marker.isStale(nowMs(), staleAfter)) marker,
    ];
    if (markers.isEmpty || running.isEmpty || nowMs() >= deadline) {
      return DrainResult(
        quiet: markers.isEmpty,
        stale: stale,
        stillRunning: running,
        acknowledged: acknowledged,
        refusedAcknowledgements: refused,
      );
    }
    await sleep(pollInterval);
  }
}
