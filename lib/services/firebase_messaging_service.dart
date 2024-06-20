import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final Completer<void> _initialLoadCompleter = Completer<void>();
  Future<void> get initialLoadComplete => _initialLoadCompleter.future;

  final databaseReference = FirebaseDatabase.instance.ref();
  final FirebaseAuth auth = FirebaseAuth.instance;
  late String? _fbmToken;

  String? get fbmToken => _fbmToken;

  static const tokenExpirationDuaration = 60 * 60 * 1000 * 24 * 30; //30 days
  late DatabaseReference _tokensRef;

  //constructor
  FirebaseMessagingService() {
    final String tokensPath = dotenv.env['TOKENS_PATH'] as String;
    _tokensRef = FirebaseDatabase.instance.ref().child(tokensPath);
  }
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

  Future<int> pruneTokens() async {
    // Get all tokens
    DatabaseEvent dbEvent = await _tokensRef.once();
    Map<dynamic, dynamic> tokens =
        dbEvent.snapshot.value as Map<dynamic, dynamic>;
    int now = DateTime.now().millisecondsSinceEpoch;
    List<String> prunedTokens = [];

    // Iterate through all tokens
    tokens.forEach((tipperId, tipperTokens) {
      tipperTokens.forEach((tokenId, tokenTimestampStr) {
        int tokenTimestamp =
            DateTime.parse(tokenTimestampStr).millisecondsSinceEpoch;
        if (now - tokenTimestamp > tokenExpirationDuaration) {
          prunedTokens.add('$tipperId/$tokenId');
        } else {
          log('Token ending in ${tokenId.toString().substring(tokenId.toString().length - 5)} is still valid');
        }
      });
    });

    // Delete all pruned tokens
    for (var tokenPath in prunedTokens) {
      log('Pruned token $tokenPath');
      await _tokensRef.child(tokenPath).remove();
    }

    log('Pruned ${prunedTokens.length} tokens');
    return prunedTokens.length;
  }

  //method to send push notification to the given tipper token
  Future<void> sendPushNotification(String token) async {
    final response = await http.post(
      Uri.parse('https://fcm.googleapis.com/fcm/send'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'key=YOUR_SERVER_KEY',
      },
      body: jsonEncode(
        <String, dynamic>{
          'notification': <String, dynamic>{
            'body': 'this is a body',
            'title': 'this is a title'
          },
          'priority': 'high',
          'data': <String, dynamic>{
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            'id': '1',
            'status': 'done'
          },
          'to': token,
        },
      ),
    );

    if (response.statusCode == 200) {
      log('Notification sent successfully');
    } else {
      log('Notification not sent');
      // If that call was not successful, throw an error.
      throw Exception('Failed to send notification: ${response.body}');
    }
  }
}
