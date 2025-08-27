import 'package:firebase_analytics/firebase_analytics.dart';

abstract class AnalyticsService {
  Future<void> logEvent(String name, {Map<String, Object>? parameters});
}

class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsService({FirebaseAnalytics? analytics}) : _analytics = analytics;

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) {
    final analytics = _analytics ?? FirebaseAnalytics.instance;
    return analytics.logEvent(name: name, parameters: parameters);
  }
}
