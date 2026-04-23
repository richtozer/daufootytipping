import 'package:daufootytipping/services/startup_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warmUpToken retries after retryable failures and force refreshes later attempts', () async {
    int attempts = 0;
    final List<bool> forceRefreshValues = <bool>[];

    final String? token = await StartupAppCheckSupport.warmUpToken(
      getToken: (bool forceRefresh) async {
        attempts += 1;
        forceRefreshValues.add(forceRefresh);

        if (attempts < 3) {
          throw Exception('Play Integrity token unavailable');
        }

        return 'token';
      },
      maxAttempts: 3,
      retryDelay: Duration.zero,
    );

    expect(token, 'token');
    expect(forceRefreshValues, <bool>[false, true, true]);
  });

  test('warmUpToken stops early for non-retryable failures', () async {
    int attempts = 0;

    final String? token = await StartupAppCheckSupport.warmUpToken(
      getToken: (bool forceRefresh) async {
        attempts += 1;
        throw Exception('bad api key');
      },
      maxAttempts: 3,
      retryDelay: Duration.zero,
    );

    expect(token, isNull);
    expect(attempts, 1);
  });

  test('protected resource retry classification matches app check style failures', () {
    expect(
      StartupAppCheckSupport.isRetryableProtectedResourceError(
        '[firebase_database/permission-denied] App Check token rejected.',
      ),
      isTrue,
    );
    expect(
      StartupAppCheckSupport.isRetryableProtectedResourceError(
        Exception('unexpected parsing failure'),
      ),
      isFalse,
    );
  });
}
