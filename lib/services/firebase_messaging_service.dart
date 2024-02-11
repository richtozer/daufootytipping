import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FirebaseService extends ChangeNotifier {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  final databaseReference = FirebaseDatabase.instance.ref();
  final FirebaseAuth auth = FirebaseAuth.instance;
  late String? _fbmToken;

  String? get fbmToken => _fbmToken;

  Future<void> initializeFirebaseMessaging() async {
    // For apple platforms, ensure the APNS token is available before making any FCM plugin API calls
    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();

    if (apnsToken != null) {
      log('APNS token: $apnsToken');
      // APNS token is available, make FCM plugin API requests...
    }

    _fbmToken = await FirebaseMessaging.instance.getToken();
    if (_fbmToken != null) {
      log('Firebase messaging token: $_fbmToken');
    } else {
      log('Firebase token is null');
    }

    notifyListeners();

    // listening for token refresh events
    messaging.onTokenRefresh.listen((newToken) {
      // save new token, and notify TipperViewModel who will save it to the database
      log('New messaging token received, updating database: $newToken');
      _fbmToken = newToken;
      notifyListeners();
    });
  }

  //method to request IOS notification permissions
  Future<void> requestIOSNotificationPermission() async {
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    log('APNS user granted notification permission: ${settings.authorizationStatus}');
  }
}
