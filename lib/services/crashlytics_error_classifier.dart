import 'package:firebase_core/firebase_core.dart';

/// Classifies uncaught errors before forwarding them to Crashlytics.
class CrashlyticsErrorClassifier {
  static const String _databasePlugin = 'firebase_database';
  static const String _disconnectCode = 'disconnected';
  static const String _disconnectSignature =
      '[$_databasePlugin/$_disconnectCode]';
  static const String _disconnectMessageFragment = 'network disconnect';

  const CrashlyticsErrorClassifier._();

  static bool isTransientRealtimeDatabaseDisconnect(Object error) {
    if (error is FirebaseException) {
      return error.plugin == _databasePlugin && error.code == _disconnectCode;
    }

    final String text = error.toString().toLowerCase();
    return text.contains(_disconnectSignature) ||
        (text.contains(_databasePlugin) &&
            text.contains(_disconnectCode) &&
            text.contains(_disconnectMessageFragment));
  }

  static bool shouldRecordPlatformErrorAsFatal(Object error) {
    return !isTransientRealtimeDatabaseDisconnect(error);
  }
}
