import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/startup_app_check.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class ConfigViewModel extends ChangeNotifier {
  final DatabaseReference _db;
  late StreamSubscription<DatabaseEvent> _configStream;
  final Duration _initialLoadTimeout;
  final Duration _retryableStartupReconnectDelay;
  final int _maxRetryableStartupReconnectAttempts;
  Timer? _retryableStartupReconnectTimer;
  int _retryableStartupReconnectAttempts = 0;
  Object? _lastInitialLoadError;

  String? _activeDAUComp;
  String? get activeDAUComp => _activeDAUComp;

  String? _minAppVersion;
  String? get minAppVersion => _minAppVersion;

  bool? _createLinkedTipper;
  bool? get createLinkedTipper => _createLinkedTipper;

  String? _googleClientId;
  String? get googleClientId => _googleClientId;

  Completer<void> _initialLoadCompleter = Completer<void>();

  Future<void> get initialLoadComplete => _initialLoadCompleter.future;
  bool get hasRequiredBootstrapConfig =>
      _activeDAUComp != null && _createLinkedTipper != null;

  ConfigViewModel({
    DatabaseReference? db,
    Duration initialLoadTimeout = const Duration(seconds: 15),
    Duration retryableStartupReconnectDelay = const Duration(seconds: 2),
    int maxRetryableStartupReconnectAttempts = 3,
  }) : _db = db ?? configuredDatabaseRef(p.configPathRoot),
       _initialLoadTimeout = initialLoadTimeout,
       _retryableStartupReconnectDelay = retryableStartupReconnectDelay,
       _maxRetryableStartupReconnectAttempts =
           maxRetryableStartupReconnectAttempts {
    _beginInitialLoad();
  }

  void _beginInitialLoad({bool resetState = false}) {
    _retryableStartupReconnectTimer?.cancel();
    _retryableStartupReconnectAttempts = 0;
    _lastInitialLoadError = null;

    if (resetState) {
      _activeDAUComp = null;
      _minAppVersion = null;
      _createLinkedTipper = null;
      _googleClientId = null;
    }

    _initialLoadCompleter = Completer<void>();
    _listenToConfigChanges();
    _armInitialLoadTimeout(_initialLoadCompleter);
  }

  void _armInitialLoadTimeout(Completer<void> completer) {
    completer.future.timeout(_initialLoadTimeout).catchError((_) {
      if (!identical(_initialLoadCompleter, completer) || completer.isCompleted) {
        return;
      }

      final Object? lastInitialLoadError = _lastInitialLoadError;
      final String message = lastInitialLoadError == null
          ? 'Config load timed out. Please check your connection or we may be having backend issues.'
          : 'Config load timed out. Last startup error: $lastInitialLoadError';
      completer.completeError(message);
      notifyListeners();
    });
  }

  void _listenToConfigChanges() {
    _configStream = _db.onValue.listen(
      (event) {
        final bool isFirstLoad = !_initialLoadCompleter.isCompleted;
        final Stopwatch processingStopwatch = Stopwatch()..start();
        final dynamic rawValue = event.snapshot.value;
        final int? payloadBytes = StartupProfiling.estimatePayloadBytes(
          rawValue,
        );
        StartupProfiling.instant(
          'startup.config_snapshot_received',
          arguments: <String, Object?>{
            'exists': event.snapshot.exists,
            'payloadBytes': payloadBytes ?? -1,
            'firstLoad': isFirstLoad,
          },
        );

        if (event.snapshot.exists) {
          _processSnapshot(event.snapshot);
        } else {
          log(
            'ConfigViewModel._listenToConfigChanges() No config found in database',
          );
        }

        if (!_initialLoadCompleter.isCompleted && hasRequiredBootstrapConfig) {
          _retryableStartupReconnectTimer?.cancel();
          _retryableStartupReconnectAttempts = 0;
          _initialLoadCompleter.complete();
        }
        processingStopwatch.stop();
        StartupProfiling.instant(
          'startup.config_snapshot_processed',
          arguments: <String, Object?>{
            'elapsedMs': processingStopwatch.elapsedMilliseconds,
            'firstLoad': isFirstLoad,
            'bootstrapReady': hasRequiredBootstrapConfig,
          },
        );
        notifyListeners();
      },
      onError: (error) {
        _lastInitialLoadError = error;
        log('ConfigViewModel._listenToConfigChanges() Error: $error');

        // For network disconnection errors, attempt reconnection after delay
        if (error.toString().contains('network disconnect') ||
            error.toString().contains('U3.e')) {
          log(
            'Network disconnection detected, attempting reconnection in 5 seconds',
          );
          Timer(const Duration(seconds: 5), () {
            if (!_initialLoadCompleter.isCompleted) {
              _reconnectDatabase();
            }
          });
        } else if (StartupAppCheckSupport.isRetryableProtectedResourceError(
          error,
        )) {
          _scheduleRetryableStartupReconnect(error);
        } else {
          // For other errors, complete with error immediately
          if (!_initialLoadCompleter.isCompleted) {
            _initialLoadCompleter.completeError(error);
            notifyListeners();
          }
        }
      },
    );
  }

  void _scheduleRetryableStartupReconnect(Object error) {
    if (_initialLoadCompleter.isCompleted) {
      return;
    }

    if (_retryableStartupReconnectAttempts >=
        _maxRetryableStartupReconnectAttempts) {
      _initialLoadCompleter.completeError(error);
      notifyListeners();
      return;
    }

    _retryableStartupReconnectAttempts += 1;
    _retryableStartupReconnectTimer?.cancel();
    log(
      'Retryable startup error detected, retrying config stream in ${_retryableStartupReconnectDelay.inMilliseconds}ms '
      '(attempt $_retryableStartupReconnectAttempts/$_maxRetryableStartupReconnectAttempts).',
    );
    _retryableStartupReconnectTimer = Timer(
      _retryableStartupReconnectDelay,
      () {
        if (!_initialLoadCompleter.isCompleted) {
          _reconnectDatabase();
        }
      },
    );
  }

  void _reconnectDatabase() {
    try {
      _configStream.cancel();
      _listenToConfigChanges();
    } catch (e) {
      log('Failed to reconnect database: $e');
      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.completeError(e);
        notifyListeners();
      }
    }
  }

  Future<void> retryInitialLoad() async {
    if (!_initialLoadCompleter.isCompleted) {
      return;
    }

    await _configStream.cancel();
    _beginInitialLoad(resetState: true);
    notifyListeners();
  }

  void _processSnapshot(DataSnapshot snapshot) {
    _activeDAUComp = _parseOptionalString(
      snapshot.child(p.currentDAUCompKey).value,
    );
    _minAppVersion = _parseOptionalString(
      snapshot.child(p.minAppVersionKey).value,
    );
    _createLinkedTipper = _parseOptionalBool(
      snapshot.child(p.createLinkedTipperKey).value,
    );
    _googleClientId = _parseOptionalString(
      snapshot.child(p.googleClientIdKey).value,
    );
  }

  String? _parseOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
      return null;
    }
    return trimmed;
  }

  bool? _parseOptionalBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
      }
    }
    return null;
  }

  Future<void> setConfigCurrentDAUComp(String value) async {
    await _db.child(p.currentDAUCompKey).set(value);
  }

  Future<void> setConfigMinAppVersion(String value) async {
    await _db.child(p.minAppVersionKey).set(value);
  }

  Future<void> setCreateLinkedTipper(bool value) async {
    await _db.child(p.createLinkedTipperKey).set(value);
  }

  @override
  void dispose() {
    _retryableStartupReconnectTimer?.cancel();
    _configStream.cancel();
    super.dispose();
  }
}
