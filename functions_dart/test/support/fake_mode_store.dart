import 'package:dart_functions/identity/admission.dart';
import 'package:dart_functions/identity/mode_control.dart';
import 'package:dart_functions/identity/server_mode.dart';

/// An in-memory [ModeStore] for tests of the drain and the command line.
class FakeModeStore implements ModeStore {
  FakeModeStore({
    this.config = const ServerModeConfig.off(),
    List<InflightMarker> markers = const [],
  }) : markers = [...markers];

  ServerModeConfig config;
  final List<InflightMarker> markers;
  final List<Map<String, Object?>> updates = [];
  final List<Map<String, Object?>> log = [];
  final List<String> removed = [];

  /// Called after every read of the in-flight markers, so a test can make the
  /// world change between polls.
  void Function(int readCount)? onInflightRead;
  int inflightReads = 0;

  @override
  Future<ServerModeConfig> readMode() async => config;

  @override
  Future<List<InflightMarker>> readInflight() async {
    final snapshot = [...markers];
    inflightReads += 1;
    onInflightRead?.call(inflightReads);
    return snapshot;
  }

  @override
  Future<void> updateIdentityNode(Map<String, Object?> fields) async {
    updates.add(fields);
    config = ServerModeConfig.parse(
      mode: fields['mode'],
      pilotUids: fields['pilotUids'] ?? config.pilotUids.toList(),
    );
  }

  @override
  Future<void> appendModeLog(int atMs, Map<String, Object?> entry) async {
    log.add({'atMs': atMs, ...entry});
  }

  @override
  Future<void> removeMarker(String operationId) async {
    removed.add(operationId);
    markers.removeWhere((marker) => marker.operationId == operationId);
  }
}
