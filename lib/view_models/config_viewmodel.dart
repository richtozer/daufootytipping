import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class ConfigViewModel extends ChangeNotifier {
  static const String _cachedConfigKey = 'cached_app_config_v1';
  final DatabaseReference _db;
  late StreamSubscription<DatabaseEvent> _configStream;
  final Duration _initialLoadTimeout;
  final Future<SharedPreferences> Function() _prefsFactory;
  bool _hasReceivedRemoteSnapshot = false;

  String? _activeDAUComp;
  String? get activeDAUComp => _activeDAUComp;

  String? _minAppVersion;
  String? get minAppVersion => _minAppVersion;

  bool? _createLinkedTipper;
  bool? get createLinkedTipper => _createLinkedTipper;

  String? _googleClientId;
  String? get googleClientId => _googleClientId;

  final Completer<void> _initialLoadCompleter = Completer<void>();

  Future<void> get initialLoadComplete => _initialLoadCompleter.future;
  bool get hasRequiredBootstrapConfig =>
      _activeDAUComp != null && _createLinkedTipper != null;

  ConfigViewModel({
    DatabaseReference? db,
    Duration initialLoadTimeout = const Duration(seconds: 15),
  }) : _db = db ?? configuredDatabaseRef(p.configPathRoot),
       _initialLoadTimeout = initialLoadTimeout {
    _listenToConfigChanges();
    // Add a timeout for initial load
    _initialLoadCompleter.future.timeout(_initialLoadTimeout).catchError((_) {
      if (_initialLoadCompleter.isCompleted) {
        return;
      }

      _initialLoadCompleter.completeError(
        'Config load timed out. Please check your connection or we may be having backend issues.',
      );
      notifyListeners();
    });
  }

  void _listenToConfigChanges() {
    _configStream = _db.onValue.listen(
      (event) {
        _hasReceivedRemoteSnapshot = true;
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
          unawaited(_cacheCurrentConfig());
        } else {
          log(
            'ConfigViewModel._listenToConfigChanges() No config found in database',
          );
        }

        if (!_initialLoadCompleter.isCompleted && hasRequiredBootstrapConfig) {
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

  Future<void> _restoreCachedConfig() async {
    try {
      final SharedPreferences prefs = await _prefsFactory();
      final String? cachedConfigJson = prefs.getString(_cachedConfigKey);
      if (cachedConfigJson == null) {
        return;
      }

      final Map<String, dynamic> cachedConfig = Map<String, dynamic>.from(
        jsonDecode(cachedConfigJson) as Map,
      );

      if (_hasReceivedRemoteSnapshot) {
        return;
      }

      _applyConfigMap(cachedConfig);
      StartupProfiling.instant(
        'startup.config_cache_loaded',
        arguments: <String, Object?>{
          'bootstrapReady': hasRequiredBootstrapConfig,
          'activeComp': _activeDAUComp ?? '',
        },
      );
      if (!_initialLoadCompleter.isCompleted && hasRequiredBootstrapConfig) {
        _initialLoadCompleter.complete();
      }
      notifyListeners();
    } catch (error, stackTrace) {
      log(
        'ConfigViewModel._restoreCachedConfig() Error restoring cache: $error',
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheCurrentConfig() async {
    try {
      final SharedPreferences prefs = await _prefsFactory();
      await prefs.setString(_cachedConfigKey, jsonEncode(_toCacheJson()));
    } catch (error, stackTrace) {
      log(
        'ConfigViewModel._cacheCurrentConfig() Error caching config: $error',
        stackTrace: stackTrace,
      );
    }
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

  void _processSnapshot(DataSnapshot snapshot) {
    _applyConfigMap(<String, Object?>{
      p.currentDAUCompKey: snapshot.child(p.currentDAUCompKey).value,
      p.minAppVersionKey: snapshot.child(p.minAppVersionKey).value,
      p.createLinkedTipperKey: snapshot.child(p.createLinkedTipperKey).value,
      p.googleClientIdKey: snapshot.child(p.googleClientIdKey).value,
    });
  }

  void _applyConfigMap(Map<String, dynamic> config) {
    _activeDAUComp = _parseOptionalString(config[p.currentDAUCompKey]);
    _minAppVersion = _parseOptionalString(config[p.minAppVersionKey]);
    _createLinkedTipper = _parseOptionalBool(config[p.createLinkedTipperKey]);
    _googleClientId = _parseOptionalString(config[p.googleClientIdKey]);
  }

  Map<String, Object?> _toCacheJson() {
    return <String, Object?>{
      p.currentDAUCompKey: _activeDAUComp,
      p.minAppVersionKey: _minAppVersion,
      p.createLinkedTipperKey: _createLinkedTipper,
      p.googleClientIdKey: _googleClientId,
    };
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
    _configStream.cancel();
    super.dispose();
  }
}
