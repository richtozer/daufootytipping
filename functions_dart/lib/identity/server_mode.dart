import 'package:dart_functions/errors.dart';
import 'package:dart_functions/rtdb/rest_database.dart';
import 'package:dau_shared/constants/identity_reasons.dart';
import 'package:dau_shared/constants/paths.dart' as paths;

/// Where the identity server mode lives: `{ mode, pilotUids }`, with the
/// in-flight markers beneath it. Closed to every client under every ruleset;
/// only the functions (Admin credentials) and the owner's mode tool use it.
final String identityModePath = '${paths.serverConfigPath}/identity';

/// `/ServerConfig/identity/inflight/{operationId}`: one marker per admitted
/// mutating request, written before the mode is read and removed when the
/// request ends (DESIGN-database-rules-phase4.md, section 5).
final String inflightPath = '$identityModePath/inflight';

/// The mode changes are logged here, by the mode tool.
final String identityModeLogPath = '${paths.serverConfigPath}/identityModeLog';

/// The hard timeout every mutating identity callable is deployed with.
const Duration mutatingCallableTimeout = Duration(seconds: 60);

/// How long past the hard timeout a marker may stay before it is called stale.
/// Stale means "overdue", never "dead": a timed-out Cloud Run request can keep
/// running, so a stale marker is investigated, not deleted.
const Duration staleMarkerMargin = Duration(seconds: 30);

/// A marker older than this is stale: the hard timeout plus the margin.
const Duration staleMarkerAfter = Duration(seconds: 90);

/// What the mutating identity callables may do (section 5).
enum IdentityMode {
  /// Refuse everyone. The default, and what an unreadable mode means.
  off('off'),

  /// Allow only the uids in `pilotUids`.
  pilot('pilot'),

  /// Allow; write the legacy public shape and the private and index data.
  coexist('coexist'),

  /// Refuse with "try again shortly"; reads still work.
  freeze('freeze'),

  /// Allow; write the minimal public shape.
  finalShape('final');

  const IdentityMode(this.wire);

  /// The string stored in the database.
  final String wire;

  /// Whether the callables also write the legacy public shape (so a 1.4.x
  /// client scanning the public list still finds the tipper).
  bool get writesLegacyPublicShape =>
      this == IdentityMode.pilot || this == IdentityMode.coexist;

  /// Whether this mode forbids something a request admitted earlier might still
  /// be doing, so the mode tool drains after switching to it.
  bool get needsDrain =>
      this == IdentityMode.off ||
      this == IdentityMode.freeze ||
      this == IdentityMode.finalShape;

  /// The mode stored as [raw], or null if it is not exactly a known mode.
  static IdentityMode? fromWire(Object? raw) {
    for (final mode in IdentityMode.values) {
      if (mode.wire == raw) {
        return mode;
      }
    }
    return null;
  }
}

/// The mode and, for `pilot`, who may use the callables.
class ServerModeConfig {
  const ServerModeConfig({required this.mode, this.pilotUids = const {}});

  /// Everything off: what a missing, unreadable or unknown mode means.
  const ServerModeConfig.off() : mode = IdentityMode.off, pilotUids = const {};

  final IdentityMode mode;
  final Set<String> pilotUids;

  /// Reads the stored values. Anything that is not exactly a known mode is
  /// `off`, so a mistake in the database can only close things, never open them.
  static ServerModeConfig parse({Object? mode, Object? pilotUids}) {
    final parsed = IdentityMode.fromWire(mode);
    if (parsed == null) {
      return const ServerModeConfig.off();
    }
    final values = pilotUids is List
        ? pilotUids
        : pilotUids is Map
        ? pilotUids.values
        : const <Object?>[];
    return ServerModeConfig(
      mode: parsed,
      pilotUids: <String>{
        for (final value in values)
          if (value is String && value.isNotEmpty) value,
      },
    );
  }
}

/// Reads the current mode. Two leaf reads, so the in-flight markers beneath the
/// node are never downloaded.
Future<ServerModeConfig> readServerMode(RestDatabase database) async {
  final mode = (await database.ref('$identityModePath/mode').once()).value;
  if (IdentityMode.fromWire(mode) != IdentityMode.pilot) {
    return ServerModeConfig.parse(mode: mode);
  }
  final pilotUids =
      (await database.ref('$identityModePath/pilotUids').once()).value;
  return ServerModeConfig.parse(mode: mode, pilotUids: pilotUids);
}

/// Throws the refusal the mode calls for, or returns if [uid] may proceed.
///
/// `off` and a non-pilot caller in `pilot` are "not available" (not retryable
/// until the mode changes); `freeze` is "unavailable" (retry shortly).
void checkAdmission(ServerModeConfig config, String uid) {
  switch (config.mode) {
    case IdentityMode.off:
      throw _notAvailable();
    case IdentityMode.pilot:
      if (!config.pilotUids.contains(uid)) {
        throw _notAvailable();
      }
    case IdentityMode.coexist:
    case IdentityMode.finalShape:
      return;
    case IdentityMode.freeze:
      throw UnavailableError(
        'A maintenance step is in progress. Please try again shortly.',
        reason: identityReasonUnavailable,
      );
  }
}

FailedPreconditionError _notAvailable() => FailedPreconditionError(
  'This is not available yet.',
  reason: identityReasonNotAvailable,
);
