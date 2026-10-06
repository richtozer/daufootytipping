import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:daufootytipping/services/configured_realtime_database.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dart:io' show Platform;

import 'package:watch_it/watch_it.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class FirebaseMessagingService {
  static const String outstandingTipsBadgeMessageType =
      'outstanding_tips_badge';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  Future<void>? _initializationFuture;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  DatabaseReference get databaseReference => configuredDatabaseRef();
  final FirebaseAuth auth = FirebaseAuth.instance;
  String? _fbmToken; // Initialize with null
  String? _registeredTipperId;

  String? get fbmToken => _fbmToken;

  Future<void> initializeFirebaseMessaging() {
    _initializationFuture ??= _initializeFirebaseMessagingInternal();
    return _initializationFuture!;
  }

  Future<void> _initializeFirebaseMessagingInternal() async {
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        await _requestNotificationPermission();
      }

      await _retrieveToken();

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
      }

      // Listening for token refresh events
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        log('New messaging token received, updating database.');
        final oldToken = _fbmToken;
        _fbmToken = newToken;
        if (oldToken != null &&
            oldToken != newToken &&
            _registeredTipperId != null) {
          await _removeToken(_registeredTipperId!, oldToken);
        }
        await _saveTokenToDatabase(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        log('Received a message while in the foreground: ${message.messageId}');
        if (outstandingTipsBadgeCount(message.data) != null) {
          log(
            'Foreground badge message received; live app state remains authoritative.',
          );
        }
      });

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<void> _retrieveToken() async {
    try {
      _fbmToken = await _firebaseMessaging.getToken();
      if (_fbmToken != null) {
        await _saveTokenToDatabase(_fbmToken!);
      } else {
        log('Firebase token is null');
      }
    } catch (e) {
      log('Failed to retrieve FCM token: $e');
      // Retry after a delay
      try {
        await Future.delayed(const Duration(seconds: 5));
        _fbmToken = await _firebaseMessaging.getToken();
        if (_fbmToken != null) {
          await _saveTokenToDatabase(_fbmToken!);
        } else {
          log('Firebase token is null after retry');
        }
      } catch (e) {
        log('Failed to retrieve FCM token after retry: $e');
      }
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    try {
      final user = auth.currentUser;
      if (user != null) {
        String timeNow = DateTime.now().toIso8601String();
        // find the tipper by UID, and use the dbkey as the token key
        Tipper? tipper = await di<TippersViewModel>().findTipperByUid(user.uid);

        if (tipper == null) {
          log('Tipper not found for UID: ${user.uid}');
          return;
        }

        await registerTokenForTipper(tipper, token: token, updatedAt: timeNow);
      } else {
        log('User is not logged in, cannot save token');
      }
    } catch (e) {
      log('Failed to save token to database: $e');
    }
  }

  Future<void> registerTokenForTipper(
    Tipper tipper, {
    String? token,
    String? updatedAt,
  }) async {
    final tokenToRegister = token ?? _fbmToken;
    final tipperId = tipper.dbkey;
    if (tokenToRegister == null || tipperId == null) {
      return;
    }

    if (_registeredTipperId != null && _registeredTipperId != tipperId) {
      await _removeToken(_registeredTipperId!, tokenToRegister);
    }
    await _removeTokenFromOtherTippers(tipperId, tokenToRegister);
    await databaseReference.child(p.tokensPath).child(tipperId).update({
      tokenToRegister: updatedAt ?? DateTime.now().toIso8601String(),
    });
    _registeredTipperId = tipperId;
    log(
      'FirebaseMessagingService.registerTokenForTipper() Token ending in ${tokenToRegister.substring(tokenToRegister.length - 4)} saved to database',
    );
  }

  Future<void> unregisterCurrentToken({String? tipperId}) async {
    final token = _fbmToken;
    final ownerTipperId = tipperId ?? _registeredTipperId;
    if (token == null || ownerTipperId == null) {
      return;
    }
    await _removeToken(ownerTipperId, token);
    if (_registeredTipperId == ownerTipperId) {
      _registeredTipperId = null;
    }
  }

  Future<void> _removeToken(String tipperId, String token) async {
    await databaseReference
        .child(p.tokensPath)
        .child(tipperId)
        .child(token)
        .remove();
    log(
      'FirebaseMessagingService removed token ending in ${token.substring(token.length - 4)} for tipper $tipperId',
    );
  }

  Future<void> _removeTokenFromOtherTippers(
    String currentTipperId,
    String token,
  ) async {
    final snapshot = await databaseReference.child(p.tokensPath).once();
    final value = snapshot.snapshot.value;
    if (value is! Map) {
      return;
    }
    for (final entry in value.entries) {
      final tipperId = entry.key.toString();
      if (tipperId == currentTipperId || entry.value is! Map) {
        continue;
      }
      final tokens = entry.value as Map<dynamic, dynamic>;
      if (tokens.containsKey(token)) {
        await _removeToken(tipperId, token);
      }
    }
  }

  static int? outstandingTipsBadgeCount(Map<String, dynamic> data) {
    if (data['type'] != outstandingTipsBadgeMessageType) {
      return null;
    }
    final count = int.tryParse(data['count']?.toString() ?? '');
    return count != null && count >= 0 ? count : null;
  }

  Future<void> _requestNotificationPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    log('User notification permission status: ${settings.authorizationStatus}');
  }
}

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Handling a background message: ${message.messageId}');
  final count = FirebaseMessagingService.outstandingTipsBadgeCount(
    message.data,
  );
  if (count == null) {
    return;
  }
  final didSetBadge = await AppBadgeService().setCount(count);
  if (!didSetBadge) {
    log('Background app badge update failed for count $count');
  }
}
