import 'dart:async';
import 'dart:developer';

typedef AppCheckTokenGetter = Future<String?> Function(bool forceRefresh);

/// Hardens startup against short-lived App Check token fetch failures.
class StartupAppCheckSupport {
  const StartupAppCheckSupport._();

  static bool isLikelyAppCheckError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('app check') ||
        text.contains('appcheck') ||
        text.contains('play integrity') ||
        text.contains('attestation') ||
        text.contains('too many attempts');
  }

  static bool isRetryableWarmupError(Object error) {
    final String text = error.toString().toLowerCase();
    return isLikelyAppCheckError(error) ||
        text.contains('network') ||
        text.contains('timeout') ||
        text.contains('unavailable');
  }

  static bool isRetryableProtectedResourceError(Object error) {
    final String text = error.toString().toLowerCase();
    return isLikelyAppCheckError(error) ||
        text.contains('permission denied') ||
        text.contains('permission-denied');
  }

  static Future<String?> warmUpToken({
    required AppCheckTokenGetter getToken,
    int maxAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 750),
  }) async {
    assert(maxAttempts > 0);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final bool forceRefresh = attempt > 1;

      try {
        final String? token = await getToken(forceRefresh);
        if (token != null && token.isNotEmpty) {
          log('FirebaseAppCheck token warmed up on attempt $attempt.');
          return token;
        }

        log(
          'FirebaseAppCheck token warm-up returned an empty token on attempt $attempt/$maxAttempts.',
        );
      } catch (error, stackTrace) {
        log(
          'FirebaseAppCheck token warm-up failed on attempt $attempt/$maxAttempts.',
          error: error,
          stackTrace: stackTrace,
        );

        if (!isRetryableWarmupError(error)) {
          return null;
        }
      }

      if (attempt < maxAttempts) {
        await Future<void>.delayed(
          Duration(milliseconds: retryDelay.inMilliseconds * attempt),
        );
      }
    }

    log('FirebaseAppCheck token warm-up exhausted retries.');
    return null;
  }
}
