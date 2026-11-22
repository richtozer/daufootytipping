import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:daufootytipping/services/device_token_registrar.dart';
import 'package:daufootytipping/services/identity_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dart:io' show Platform;

import 'package:watch_it/watch_it.dart';

class FirebaseMessagingService {
  FirebaseMessagingService({DeviceTokenRegistrar? tokens})
    : _tokensOverride = tokens;

  static const String outstandingTipsBadgeMessageType =
      'outstanding_tips_badge';
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DeviceTokenRegistrar? _tokensOverride;
  DeviceTokenRegistrar? _tokens;

  /// Tells the server which push tokens are the signed-in tipper's.
  DeviceTokenRegistrar get _registrar => _tokens ??=
      _tokensOverride ??
      DeviceTokenRegistrar(
        identity: di<IdentityService>(),
        currentAccount: () => auth.currentUser?.uid,
      );
  Future<void>? _initializationFuture;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  final FirebaseAuth auth = FirebaseAuth.instance;
  String? _fbmToken; // Initialize with null
  String? _registeredToken;

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
        log('New messaging token received, updating the server.');
        final oldToken = _registeredToken;
        _fbmToken = newToken;
        if (oldToken != null && oldToken != newToken) {
          try {
            await _registrar.unregister(oldToken);
          } on IdentityFailure catch (failure) {
            // The old token is dead anyway; the server drops tokens that go
            // unrefreshed.
            log('Could not remove the old messaging token: ${failure.code}');
          }
        }
        await _registerTokenIfLinked(newToken);
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
        await _registerTokenIfLinked(_fbmToken!);
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
          await _registerTokenIfLinked(_fbmToken!);
        } else {
          log('Firebase token is null after retry');
        }
      } catch (e) {
        log('Failed to retrieve FCM token after retry: $e');
      }
    }
  }

  Future<void> _registerTokenIfLinked(String token) async {
    try {
      final user = auth.currentUser;
      if (user == null) {
        log('User is not logged in, cannot save token');
        return;
      }
      // Only the signed-in tipper's own record can be registered for, and only
      // once the account is linked to it.
      final Tipper? tipper = await di<TippersViewModel>().findTipperByUid(
        user.uid,
      );
      if (tipper == null) {
        log('Tipper not found for UID: ${user.uid}');
        return;
      }
      await registerCurrentToken(token: token);
    } catch (e) {
      log('Failed to register the messaging token: $e');
    }
  }

  /// Registers this device's push token with the signed-in tipper. The server
  /// takes it from any other tipper that held it. A failure is logged, not
  /// thrown.
  Future<void> registerCurrentToken({String? token}) async {
    final tokenToRegister = token ?? _fbmToken;
    if (tokenToRegister == null) {
      return;
    }
    if (await _registrar.register(tokenToRegister)) {
      _registeredToken = tokenToRegister;
    }
  }

  /// Removes this device's push token from the signed-in tipper, so that their
  /// notifications stop arriving here. Throws the [IdentityFailure] if the server
  /// cannot be asked, because account deletion must not go on as if it were done.
  Future<void> unregisterCurrentToken() async {
    final token = _fbmToken;
    if (token == null) {
      return;
    }
    await _registrar.unregister(token);
    _registeredToken = null;
  }

  /// [unregisterCurrentToken] for signing out, which must not be held up by a
  /// server that cannot be reached: tries for [limit], then leaves the token for
  /// the next tipper to register on this device (the server moves it) or for the
  /// server's stale-token cleanup.
  Future<void> unregisterCurrentTokenIfPossible({
    Duration limit = const Duration(seconds: 10),
  }) async {
    try {
      await unregisterCurrentToken().timeout(limit);
    } on Object catch (error) {
      log('Could not remove the messaging token while signing out: $error');
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
