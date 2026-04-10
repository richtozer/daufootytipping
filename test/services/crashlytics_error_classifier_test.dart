import 'package:daufootytipping/services/crashlytics_error_classifier.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:test/test.dart';

void main() {
  group('CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect', () {
    test('matches firebase_database disconnected FirebaseException', () {
      final FirebaseException error = FirebaseException(
        plugin: 'firebase_database',
        code: 'disconnected',
        message: 'The operation had to be aborted due to a network disconnect.',
      );

      expect(
        CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(error),
        isTrue,
      );
      expect(
        CrashlyticsErrorClassifier.shouldRecordPlatformErrorAsFatal(error),
        isFalse,
      );
    });

    test('matches stringified firebase_database disconnected errors', () {
      const String error =
          '[firebase_database/disconnected] The operation had to be aborted due to a network disconnect.';

      expect(
        CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(error),
        isTrue,
      );
    });

    test('does not match other firebase_database errors', () {
      final FirebaseException error = FirebaseException(
        plugin: 'firebase_database',
        code: 'network-error',
        message: 'The operation could not be performed due to a network error.',
      );

      expect(
        CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(error),
        isFalse,
      );
      expect(
        CrashlyticsErrorClassifier.shouldRecordPlatformErrorAsFatal(error),
        isTrue,
      );
    });

    test('does not match unrelated exceptions', () {
      final FirebaseException error = FirebaseException(
        plugin: 'firebase_auth',
        code: 'network-request-failed',
        message: 'A network error has occurred.',
      );

      expect(
        CrashlyticsErrorClassifier.isTransientRealtimeDatabaseDisconnect(error),
        isFalse,
      );
    });
  });
}
