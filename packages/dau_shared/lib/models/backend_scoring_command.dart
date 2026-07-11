enum BackendScoringCommandType {
  tipWritten,
  officialScoreWritten,
  liveScoreWritten,
  adminRescore,
}

extension BackendScoringCommandTypeApi on BackendScoringCommandType {
  String get apiValue => name;
}

enum BackendScoringIdempotencyStatus {
  started,
  completed,
  failed,
}

extension BackendScoringIdempotencyStatusApi
    on BackendScoringIdempotencyStatus {
  String get apiValue => name;
}

class BackendScoringCommand {
  final BackendScoringCommandType commandType;
  final String compKey;
  final int? roundNumber;
  final String? tipperId;
  final String? gameKey;
  final String sourceEventId;
  final String sourcePath;
  final String scopeKey;
  final String commandId;

  const BackendScoringCommand({
    required this.commandType,
    required this.compKey,
    required this.roundNumber,
    required this.tipperId,
    required this.gameKey,
    required this.sourceEventId,
    required this.sourcePath,
    required this.scopeKey,
    required this.commandId,
  });

  bool get isTipWritten => commandType == BackendScoringCommandType.tipWritten;

  factory BackendScoringCommand.fromJson(Map<String, dynamic> json) {
    final commandType = _parseCommandType(json['commandType']);
    final compKey = _requireString(json, 'compKey');
    final roundNumber = _optionalPositiveInt(json, 'roundNumber');
    final tipperId = _optionalString(json, 'tipperId');
    final gameKey = _optionalString(json, 'gameKey');
    final sourceEventId = _requireString(json, 'sourceEventId');
    final sourcePath = _requireString(json, 'sourcePath');
    final scopeKey = _requireString(json, 'scopeKey');
    final commandId = _requireString(json, 'commandId');

    switch (commandType) {
      case BackendScoringCommandType.tipWritten:
        if (tipperId == null) {
          throw ArgumentError('tipWritten requires tipperId');
        }
        if (gameKey == null) {
          throw ArgumentError('tipWritten requires gameKey');
        }
        break;
      case BackendScoringCommandType.officialScoreWritten:
        if (gameKey == null) {
          throw ArgumentError('officialScoreWritten requires gameKey');
        }
        break;
      case BackendScoringCommandType.liveScoreWritten:
        if (gameKey == null) {
          throw ArgumentError('liveScoreWritten requires gameKey');
        }
        break;
      case BackendScoringCommandType.adminRescore:
        break;
    }

    return BackendScoringCommand(
      commandType: commandType,
      compKey: compKey,
      roundNumber: roundNumber,
      tipperId: tipperId,
      gameKey: gameKey,
      sourceEventId: sourceEventId,
      sourcePath: sourcePath,
      scopeKey: scopeKey,
      commandId: commandId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'commandType': commandType.apiValue,
    'compKey': compKey,
    if (roundNumber != null) 'roundNumber': roundNumber,
    if (tipperId != null) 'tipperId': tipperId,
    if (gameKey != null) 'gameKey': gameKey,
    'sourceEventId': sourceEventId,
    'sourcePath': sourcePath,
    'scopeKey': scopeKey,
    'commandId': commandId,
  };
}

class BackendScoringIdempotencyRecord {
  final BackendScoringIdempotencyStatus status;
  final String commandId;
  final String commandType;
  final String compKey;
  final String sourceEventId;
  final String sourcePath;
  final String scopeKey;
  final String startedAt;
  final String expiresAt;
  final String? completedAt;
  final String? failedAt;
  final String? error;

  const BackendScoringIdempotencyRecord({
    required this.status,
    required this.commandId,
    required this.commandType,
    required this.compKey,
    required this.sourceEventId,
    required this.sourcePath,
    required this.scopeKey,
    required this.startedAt,
    required this.expiresAt,
    this.completedAt,
    this.failedAt,
    this.error,
  });

  factory BackendScoringIdempotencyRecord.fromJson(
    Map<String, dynamic> json,
  ) {
    final status = _parseIdempotencyStatus(json['status']);
    return BackendScoringIdempotencyRecord(
      status: status,
      commandId: _requireString(json, 'commandId'),
      commandType: _requireString(json, 'commandType'),
      compKey: _requireString(json, 'compKey'),
      sourceEventId: _requireString(json, 'sourceEventId'),
      sourcePath: _requireString(json, 'sourcePath'),
      scopeKey: _requireString(json, 'scopeKey'),
      startedAt: _requireString(json, 'startedAt'),
      expiresAt: _requireString(json, 'expiresAt'),
      completedAt: _optionalString(json, 'completedAt'),
      failedAt: _optionalString(json, 'failedAt'),
      error: _optionalString(json, 'error'),
    );
  }

  bool get isCompleted =>
      status == BackendScoringIdempotencyStatus.completed;
  bool get isStarted => status == BackendScoringIdempotencyStatus.started;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'status': status.apiValue,
    'commandId': commandId,
    'commandType': commandType,
    'compKey': compKey,
    'sourceEventId': sourceEventId,
    'sourcePath': sourcePath,
    'scopeKey': scopeKey,
    'startedAt': startedAt,
    'expiresAt': expiresAt,
    if (completedAt != null) 'completedAt': completedAt,
    if (failedAt != null) 'failedAt': failedAt,
    if (error != null) 'error': error,
  };
}

BackendScoringCommandType _parseCommandType(dynamic raw) {
  if (raw is! String || raw.isEmpty) {
    throw ArgumentError('Missing required field: commandType');
  }
  for (final type in BackendScoringCommandType.values) {
    if (type.name == raw) {
      return type;
    }
  }
  throw ArgumentError('Unsupported commandType: $raw');
}

BackendScoringIdempotencyStatus _parseIdempotencyStatus(dynamic raw) {
  if (raw is! String || raw.isEmpty) {
    throw ArgumentError('Missing required field: status');
  }
  for (final status in BackendScoringIdempotencyStatus.values) {
    if (status.name == raw) {
      return status;
    }
  }
  throw ArgumentError('Unsupported status: $raw');
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError('Missing required field: $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw ArgumentError('Field $key must be a non-empty string when present');
}

int? _optionalPositiveInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int && value > 0) {
    return value;
  }
  if (value is num && value > 0 && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw ArgumentError('Field $key must be a positive integer when present');
}
