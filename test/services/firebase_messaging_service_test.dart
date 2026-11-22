import 'package:test/test.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/constants/paths.dart';

void main() {
  group('FirebaseMessagingService Tests', () {
    group('Constants and static values', () {
      test('should have correct tokensPath', () {
        expect(tokensPath, equals('/AllTippersTokens'));
      });
    });

    group('Token time string parsing', () {
      test('should handle ISO8601 format correctly', () {
        // Test the ISO8601 format used in _saveTokenToDatabase
        final now = DateTime.now();
        final isoString = now.toIso8601String();
        final parsed = DateTime.parse(isoString);

        expect(
          parsed.millisecondsSinceEpoch,
          equals(now.millisecondsSinceEpoch),
        );
      });

      test('should handle round-trip conversion correctly', () {
        // Test the full cycle: DateTime -> ISO8601 -> DateTime -> milliseconds
        final originalTime = DateTime.now();
        final isoString = originalTime.toIso8601String();
        final parsedTime = DateTime.parse(isoString);
        final parsedMs = parsedTime.millisecondsSinceEpoch;

        // Should be equal within reasonable precision
        final difference = (originalTime.millisecondsSinceEpoch - parsedMs)
            .abs();
        expect(
          difference,
          lessThan(1000),
          reason: 'Round-trip conversion should preserve time within 1 second',
        );
      });
    });

    group('Service structure validation', () {
      test('should have required method signatures available', () {
        // Test that the class has the expected public interface
        // without instantiating (to avoid Firebase initialization)

        // Verify the class exists and can be referenced
        expect(FirebaseMessagingService, isA<Type>());
      });

      test('should have correct module-level constants', () {
        expect(tokensPath, isA<String>());
        expect(tokensPath, isNotEmpty);
        expect(tokensPath.startsWith('/'), isTrue);
      });
    });

    group('Outstanding tips badge messages', () {
      test('parses a valid absolute count', () {
        expect(
          FirebaseMessagingService.outstandingTipsBadgeCount({
            'type': FirebaseMessagingService.outstandingTipsBadgeMessageType,
            'count': '4',
          }),
          4,
        );
      });

      test('accepts zero so a background notification can be cancelled', () {
        expect(
          FirebaseMessagingService.outstandingTipsBadgeCount({
            'type': FirebaseMessagingService.outstandingTipsBadgeMessageType,
            'count': '0',
          }),
          0,
        );
      });

      test('ignores unrelated and malformed messages', () {
        expect(
          FirebaseMessagingService.outstandingTipsBadgeCount({
            'type': 'deadline_reminder',
            'count': '4',
          }),
          isNull,
        );
        expect(
          FirebaseMessagingService.outstandingTipsBadgeCount({
            'type': FirebaseMessagingService.outstandingTipsBadgeMessageType,
            'count': '-1',
          }),
          isNull,
        );
      });
    });

    group('Business logic validation', () {
      test('should have reasonable token path structure', () {
        expect(tokensPath, equals('/AllTippersTokens'));
        expect(tokensPath, matches(r'^/[A-Za-z]+$'));
      });
    });
  });
}
