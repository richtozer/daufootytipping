import 'dart:async';

import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class RealtimeConnectionService extends ChangeNotifier {
  RealtimeConnectionService({DatabaseReference? connectedRef})
    : _connectedRef =
          connectedRef ?? configuredRealtimeDatabase.ref('.info/connected') {
    _listenToConnectionChanges();
  }

  final DatabaseReference _connectedRef;
  StreamSubscription<DatabaseEvent>? _subscription;
  bool? _isConnected;
  bool _offlineTipNoticeShown = false;
  bool _disposed = false;
  int _listenerGeneration = 0;

  bool get connectionKnown => _isConnected != null;
  bool get isConnected => _isConnected != false;
  bool get isOffline => _isConnected == false;

  @visibleForTesting
  void handleConnectionValueForTest(Object? value) {
    _setConnected(value == true);
  }

  void _listenToConnectionChanges() {
    if (_disposed) {
      return;
    }

    final generation = ++_listenerGeneration;
    _subscription = _connectedRef.onValue.listen((event) {
      if (_disposed || generation != _listenerGeneration) {
        return;
      }
      _handleConnectionEvent(event);
    });
  }

  void _restartConnectionListener() {
    if (_disposed) {
      return;
    }

    unawaited(_subscription?.cancel());
    _listenToConnectionChanges();
  }

  void _handleConnectionEvent(DatabaseEvent event) {
    _setConnected(event.snapshot.value == true);
  }

  void _setConnected(bool isConnected) {
    if (_isConnected == isConnected) {
      return;
    }
    _isConnected = isConnected;
    if (isConnected) {
      _offlineTipNoticeShown = false;
    }
    notifyListeners();
  }

  bool consumeOfflineTipNotice() {
    if (!isOffline || _offlineTipNoticeShown) {
      return false;
    }
    _offlineTipNoticeShown = true;
    return true;
  }

  void markServerWriteAcknowledged() {
    if (_disposed) {
      return;
    }

    _setConnected(true);
    _restartConnectionListener();
  }

  @override
  void dispose() {
    _disposed = true;
    _listenerGeneration++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
