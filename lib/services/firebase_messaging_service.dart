import 'dart:async';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;

class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  final databaseReference = FirebaseDatabase.instance.ref();
  final FirebaseAuth auth = FirebaseAuth.instance;
  late String? _fbmToken;

  String? get fbmToken => _fbmToken;

  Future<void> initializeFirebaseMessaging() async {
    log('Initializing Firebase messaging');

    if (Platform.isIOS) {
      await requestIOSNotificationPermission();
    }

    try {
      _fbmToken = await _firebaseMessaging.getToken();
    } catch (e) {
      log('Failed to retrieve FCM token: $e');
      // Retry after a delay
      await Future.delayed(const Duration(seconds: 5));
      _fbmToken = await _firebaseMessaging.getToken();
    }

    if (_fbmToken != null) {
      log('Firebase messaging token: $_fbmToken');
    } else {
      log('Firebase token is null');
    }

    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    // listening for token refresh events
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      // save new token, and notify TipperViewModel who will save it to the database
      log('New messaging token received, updating database: $newToken');
      _fbmToken = newToken;
      //TODO - save to database
      //notifyListeners();
    });
  }

  //method to request IOS notification permissions
  Future<void> requestIOSNotificationPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    log('APNS user granted notification permission: ${settings.authorizationStatus}');
  }
}
