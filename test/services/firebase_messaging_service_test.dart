import 'package:test/test.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';

void main() {
  group('FirebaseMessagingService Tests', () {
    group('Constants and static values', () {
      test('should have correct tokensPath', () {
        expect(tokensPath, equals('/AllTippersTokens'));
      });

      test('should have correct token expiration duration', () {
        // 30 days in milliseconds: 60 * 60 * 1000 * 24 * 30
        const expectedDuration = 60 * 60 * 1000 * 24 * 30;
        expect(FirebaseMessagingService.tokenExpirationDuration, equals(expectedDuration));
        
        // Verify it equals 30 days
        const thirtyDaysInMs = 30 * 24 * 60 * 60 * 1000;
        expect(FirebaseMessagingService.tokenExpirationDuration, equals(thirtyDaysInMs));
      });
    });

    group('Token age calculation logic', () {
      test('should calculate stale time correctly', () {
        // Test the stale time calculation logic used in deleteStaleTokens
        final timeNow = DateTime.now().millisecondsSinceEpoch;
        final staleTime = timeNow - FirebaseMessagingService.tokenExpirationDuration;
        
        // Stale time should be 30 days ago
        final thirtyDaysAgo = timeNow - (30 * 24 * 60 * 60 * 1000);
        expect(staleTime, equals(thirtyDaysAgo));
      });

      test('should identify stale vs fresh tokens correctly', () {
        // Test the logic used in deleteStaleTokens
        final now = DateTime.now();
        final timeNow = now.millisecondsSinceEpoch;
        
        // Create a token that's 31 days old (should be stale)
        final staleTokenTime = now.subtract(const Duration(days: 31));
        final staleTokenTimeMs = staleTokenTime.millisecondsSinceEpoch;
        
        // Create a token that's 29 days old (should not be stale)
        final freshTokenTime = now.subtract(const Duration(days: 29));
        final freshTokenTimeMs = freshTokenTime.millisecondsSinceEpoch;
        
        final staleThreshold = timeNow - FirebaseMessagingService.tokenExpirationDuration;
        
        expect(staleTokenTimeMs < staleThreshold, isTrue, 
               reason: 'Token older than 30 days should be considered stale');
        expect(freshTokenTimeMs > staleThreshold, isTrue,
               reason: 'Token newer than 30 days should not be considered stale');
      });

      test('should handle edge case of exactly 30 days old token', () {
        final now = DateTime.now();
        final timeNow = now.millisecondsSinceEpoch;
        
        // Create a token that's exactly 30 days old
        final exactlyThirtyDaysAgo = now.subtract(const Duration(days: 30));
        final exactTokenTimeMs = exactlyThirtyDaysAgo.millisecondsSinceEpoch;
        
        final staleThreshold = timeNow - FirebaseMessagingService.tokenExpirationDuration;
        
        // Token exactly 30 days old should be considered fresh (not stale)
        expect(exactTokenTimeMs >= staleThreshold, isTrue,
               reason: 'Token exactly 30 days old should not be considered stale');
      });
    });

    group('Token time string parsing', () {
      test('should handle ISO8601 format correctly', () {
        // Test the ISO8601 format used in _saveTokenToDatabase
        final now = DateTime.now();
        final isoString = now.toIso8601String();
        final parsed = DateTime.parse(isoString);
        
        expect(parsed.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
      });

      test('should handle round-trip conversion correctly', () {
        // Test the full cycle: DateTime -> ISO8601 -> DateTime -> milliseconds
        final originalTime = DateTime.now();
        final isoString = originalTime.toIso8601String();
        final parsedTime = DateTime.parse(isoString);
        final parsedMs = parsedTime.millisecondsSinceEpoch;
        
        // Should be equal within reasonable precision
        final difference = (originalTime.millisecondsSinceEpoch - parsedMs).abs();
        expect(difference, lessThan(1000), 
               reason: 'Round-trip conversion should preserve time within 1 second');
      });
    });

    group('Service structure validation', () {
      test('should have required method signatures available', () {
        // Test that the class has the expected public interface
        // without instantiating (to avoid Firebase initialization)
        
        // Verify the class exists and can be referenced
        expect(FirebaseMessagingService, isA<Type>());
        
        // Verify static constants exist
        expect(FirebaseMessagingService.tokenExpirationDuration, isA<int>());
      });

      test('should have correct module-level constants', () {
        expect(tokensPath, isA<String>());
        expect(tokensPath, isNotEmpty);
        expect(tokensPath.startsWith('/'), isTrue);
      });
    });

    group('Business logic validation', () {
      test('should use milliseconds for time calculations', () {
        // Verify that the expiration duration is in milliseconds
        const duration = FirebaseMessagingService.tokenExpirationDuration;
        
        // Should be a reasonable number of milliseconds for 30 days
        const minExpected = 30 * 24 * 60 * 60 * 1000; // 30 days in ms
        const maxExpected = 31 * 24 * 60 * 60 * 1000; // 31 days in ms
        
        expect(duration, greaterThanOrEqualTo(minExpected));
        expect(duration, lessThan(maxExpected));
      });

      test('should have reasonable token path structure', () {
        expect(tokensPath, equals('/AllTippersTokens'));
        expect(tokensPath, matches(r'^/[A-Za-z]+$'));
      });
    });
  });
}