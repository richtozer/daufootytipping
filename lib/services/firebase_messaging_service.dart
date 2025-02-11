import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:watch_it/watch_it.dart';

final String tokensPath = dotenv.env['TOKENS_PATH'] as String;

class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  final databaseReference = FirebaseDatabase.instance.ref();
  final FirebaseAuth auth = FirebaseAuth.instance;
  String? _fbmToken; // Initialize with null

  String? get fbmToken => _fbmToken;

  static const tokenExpirationDuration = 60 * 60 * 1000 * 24 * 30; // 30 days

  Future<void> initializeFirebaseMessaging() async {
    log('Initializing Firebase messaging');

    if (Platform.isIOS) {
      await _requestIOSNotificationPermission();
    }

    await _retrieveToken();

    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    // Listening for token refresh events
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      log('New messaging token received, updating database: $newToken');
      _fbmToken = newToken;
      await _saveTokenToDatabase(newToken);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Received a message while in the foreground: ${message.messageId}');
      // Handle the message
    });

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  Future<void> _retrieveToken() async {
    try {
      _fbmToken = await _firebaseMessaging.getToken();
      if (_fbmToken != null) {
        log('Firebase messaging token: $_fbmToken');
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
          log('Firebase messaging token after retry: $_fbmToken');
          await _saveTokenToDatabase(_fbmToken!);
        } else {
          log('Firebase token is null after retry');
        }
      } catch (e) {
        log('Failed to retrieve FCM token after retry: $e');
      }
    }
  }

  // method to delete stale tokens for all users
  // this method is called after TippersViewModel is initialized
  Future<void> deleteStaleTokens(TippersViewModel tippersViewModel) async {
    try {
      log('FirebaseMessagingService.deleteStaleTokens() Deleting any stale tokens');
      int countDeleted = 0;
      final timeNow = DateTime.now().millisecondsSinceEpoch;
      final staleTime = timeNow - tokenExpirationDuration;
      final snapshot = await databaseReference.child(tokensPath).once();
      final tokens = snapshot.snapshot.value as Map<dynamic, dynamic>;
      for (final user in tokens.keys) {
        final userTokens = tokens[user] as Map<dynamic, dynamic>;
        for (final token in userTokens.keys) {
          final tokenTimeStr = userTokens[token] as String;
          final tokenTime = DateTime.parse(tokenTimeStr).millisecondsSinceEpoch;
          if (tokenTime < staleTime) {
            await databaseReference
                .child(tokensPath)
                .child(user)
                .child(token)
                .remove();
            log('Tipper $user stale token deleted: $token');
            countDeleted++;
          }
        }
      }
      log('FirebaseMessagingService.deleteStaleTokens() Deleted $countDeleted stale tokens');
    } catch (e) {
      log('Failed to delete stale tokens: $e');
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

        await databaseReference
            .child(tokensPath)
            .child(tipper.dbkey!)
            .update({token: timeNow});
        log('FirebaseMessagingService._saveTokenToDatabase() Token ending in ${token.substring(token.length - 4)} saved to database');
      } else {
        log('User is not logged in, cannot save token');
      }
    } catch (e) {
      log('Failed to save token to database: $e');
    }
  }

  Future<void> _requestIOSNotificationPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    log('APNS user granted notification permission: ${settings.authorizationStatus}');
  }
}

// Background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('Handling a background message: ${message.messageId}');
  // Handle the message
}
