import 'dart:async';
import 'dart:io';

import 'package:dart_functions/errors.dart';
import 'package:dart_functions/identity/operation_id.dart';
import 'package:dart_functions/identity/server_mode.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:firebase_functions/firebase_functions.dart'
    show HttpResponseException;

/// The marker an admitted mutating request leaves at
/// `/ServerConfig/identity/inflight/{operationId}` while it runs.
class InflightMarker {
  const InflightMarker({
    required this.operationId,
    this.callable,
    this.startedAtMs,
  });

  final String operationId;
  final String? callable;

  /// When the request started, or null if the stored marker is unreadable
  /// (an unreadable marker cannot be aged, so it counts as stale).
  final int? startedAtMs;

  /// The stored form.
  Map<String, Object?> toJson() => <String, Object?>{
    'callable': callable,
    'startedAtMs': startedAtMs,
  };

  /// Reads a stored marker. A malformed one is kept, with null fields, so it
  /// shows up in the drain instead of being ignored.
  static InflightMarker parse(String operationId, Object? raw) {
    if (raw is! Map) {
      return InflightMarker(operationId: operationId);
    }
    final callable = raw['callable'];
    final startedAt = raw['startedAtMs'];
    return InflightMarker(
      operationId: operationId,
      callable: callable is String ? callable : null,
      startedAtMs: startedAt is num ? startedAt.toInt() : null,
    );
  }

  /// Overdue: older than [staleAfter], or too malformed to age. Overdue is not
  /// dead (see [staleMarkerMargin]).
  bool isStale(int nowMs, Duration staleAfter) {
    final started = startedAtMs;
    return started == null || nowMs - started > staleAfter.inMilliseconds;
  }
}

/// What a handler is told when it has been admitted.
class Admission {
  const Admission({required this.operationId, required this.config});

  /// Unique to this request: the lease owner and the log key.
  final String operationId;

  /// The mode in force when the request was admitted. A handler uses it for the
  /// whole request, because the drain waits for it before any step that
  /// depends on the mode changing.
  final ServerModeConfig config;
}

/// Runs [body] as an admitted mutating request (section 5 of the plan).
///
/// 1. Write the in-flight marker FIRST.
/// 2. Only then read the mode. A mode change is written before the markers
///    are read, so no admitted request can be invisible to a drain: each side's
///    second read sees the other's first write.
/// 3. If the mode forbids the call, refuse; otherwise run [body].
/// 4. Remove the marker only once the handler has ended **and every write it
///    sent has finished**. Giving up on a request (a timeout) stops waiting for
///    it but does not stop it, so a write can still reach the database after
///    the handler has exited. If writes are still unsettled after
///    [writeSettleGrace] the marker is kept, and removed in the background only
///    when they finish; if that never happens the drain reports it as stale.
///    If removal fails the marker stays too.
///
/// A start line and an end line carrying the operation id are logged. The end
/// line says `writesSettled=true` or `false`: an end line with `false` does NOT
/// mean the operation has finished writing, so it never justifies clearing the
/// marker.
///
/// Any failure to write the marker or read the mode refuses the request: it
/// fails closed.
Future<T> runAdmitted<T>({
  required RestDatabase database,
  required String callable,
  required String uid,
  required Future<T> Function(Admission admission) body,
  int Function()? nowMs,
  String Function()? newId,
  void Function(String line)? log,
  Future<void> Function()? afterMarkerWritten,
  Duration writeSettleGrace = const Duration(seconds: 5),
}) async {
  final clock = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  final void Function(String line) write =
      log ?? (String line) => stdout.writeln(line);
  final operationId = (newId ?? newOperationId)();
  final markerRef = database.ref('$inflightPath/$operationId');

  try {
    await markerRef.set(
      InflightMarker(
        operationId: operationId,
        callable: callable,
        startedAtMs: clock(),
      ).toJson(),
    );
  } on Object catch (error) {
    write(
      '[identity] refused op=$operationId callable=$callable: marker not written ($error)',
    );
    // The write may still land after we gave up waiting. If it does, the
    // marker belongs to nobody, so remove it once the write has finished.
    _removeWhenSettled(database, markerRef, operationId, write);
    throw _tryAgain();
  }
  write('[identity] start op=$operationId callable=$callable');

  var outcome = 'ok';
  try {
    await afterMarkerWritten?.call();
    final ServerModeConfig config;
    try {
      config = await readServerMode(database);
    } on Object catch (error) {
      outcome = 'refused';
      write('[identity] mode unreadable op=$operationId: $error');
      throw _tryAgain();
    }
    try {
      checkAdmission(config, uid);
    } on HttpResponseException {
      outcome = 'refused';
      rethrow;
    }
    return await body(Admission(operationId: operationId, config: config));
  } on Object {
    if (outcome == 'ok') {
      outcome = 'error';
    }
    rethrow;
  } finally {
    final settled = await database.writes.settled(timeout: writeSettleGrace);
    write(
      '[identity] end op=$operationId callable=$callable outcome=$outcome '
      'writesSettled=$settled',
    );
    if (settled) {
      await _removeMarker(markerRef, operationId, write);
    } else {
      write(
        '[identity] marker kept op=$operationId: '
        '${database.writes.pendingCount} write(s) still unsettled',
      );
      _removeWhenSettled(database, markerRef, operationId, write);
    }
  }
}

/// Removes the marker in the background once every write on [database] has
/// finished. Never throws. If the process ends first, the marker stays, and the
/// drain reports it as stale.
void _removeWhenSettled(
  RestDatabase database,
  RestDatabaseReference markerRef,
  String operationId,
  void Function(String line) write,
) {
  unawaited(() async {
    try {
      final settled = await database.writes.settled(timeout: staleMarkerAfter);
      if (settled) {
        await _removeMarker(markerRef, operationId, write);
        write('[identity] marker cleared op=$operationId: writes settled');
      }
    } on Object catch (error) {
      write('[identity] marker not cleared op=$operationId: $error');
    }
  }());
}

Future<void> _removeMarker(
  RestDatabaseReference markerRef,
  String operationId,
  void Function(String line) write,
) async {
  for (var attempt = 1; attempt <= 2; attempt++) {
    try {
      await markerRef.remove();
      return;
    } on Object catch (error) {
      if (attempt == 2) {
        write('[identity] marker left behind op=$operationId: $error');
      }
    }
  }
}

UnavailableError _tryAgain() => UnavailableError(
  'A maintenance step is in progress. Please try again shortly.',
  reason: identityReasonUnavailable,
);
