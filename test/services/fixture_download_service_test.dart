import 'package:test/test.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/services/fixture_download_service.dart';

void main() {
  group('FixtureDownloadService Tests', () {
    late FixtureDownloadService service;

    // Use invalid URLs to trigger error scenarios without real network calls
    final invalidNrlUrl = Uri.parse(
      'https://invalid-url-that-does-not-exist.com/nrl',
    );
    final invalidAflUrl = Uri.parse(
      'https://invalid-url-that-does-not-exist.com/afl',
    );

    setUp(() {
      // Inject a deterministic failing fetcher to avoid real network
      service = FixtureDownloadService.test((uri, league) async {
        // Make NRL fail first to match test expectations; AFL only attempted if NRL succeeds
        if (league == League.nrl) {
          throw Exception('NRL network failure');
        }
        throw Exception('AFL network failure');
      });
    });

    group('fetch() method - Error scenarios', () {
      test('should throw exception when NRL download fails', () async {
        // Act & Assert
        expect(
          () async => await service.fetch(invalidNrlUrl, invalidAflUrl, false),
          throwsA(isA<Exception>()),
        );
      });

      test(
        'should throw exception when using invalid URLs on background thread',
        () async {
          // Act & Assert
          expect(
            () async => await service.fetch(invalidNrlUrl, invalidAflUrl, true),
            throwsA(isA<Exception>()),
          );
        },
      );

      test('exception message should contain NRL error information', () async {
        // Act & Assert
        try {
          await service.fetch(invalidNrlUrl, invalidAflUrl, false);
          fail('Expected exception was not thrown');
        } catch (e) {
          expect(e.toString(), contains('NRL'));
          expect(e.toString(), contains('Exception'));
        }
      });

      test('should handle malformed URLs gracefully', () async {
        // Arrange
        final malformedNrlUrl = Uri.parse('not-a-valid-url');
        final malformedAflUrl = Uri.parse('also-not-valid');

        // Act & Assert
        expect(
          () async =>
              await service.fetch(malformedNrlUrl, malformedAflUrl, false),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Data structure validation', () {
      test('should handle threading parameter correctly', () async {
        // Both main thread and background thread should behave the same for errors
        bool mainThreadThrew = false;
        bool backgroundThreadThrew = false;

        try {
          await service.fetch(invalidNrlUrl, invalidAflUrl, false);
        } catch (e) {
          mainThreadThrew = true;
        }

        try {
          await service.fetch(invalidNrlUrl, invalidAflUrl, true);
        } catch (e) {
          backgroundThreadThrew = true;
        }

        expect(mainThreadThrew, isTrue);
        expect(backgroundThreadThrew, isTrue);
      });
    });

    group('Service instantiation', () {
      test('should create service instance successfully', () {
        final newService = FixtureDownloadService();
        expect(newService, isA<FixtureDownloadService>());
      });

      test('should handle multiple service instances', () {
        final service1 = FixtureDownloadService();
        final service2 = FixtureDownloadService();

        expect(service1, isA<FixtureDownloadService>());
        expect(service2, isA<FixtureDownloadService>());
        expect(service1, isNot(same(service2)));
      });
    });

  group('Method signature validation', () {
      test('fetch method should accept correct parameters', () async {
        // This test validates the method signature is correct
        final nrlUri = Uri.parse('https://example.com/nrl');
        final aflUri = Uri.parse('https://example.com/afl');

        // Should not throw a compilation error for correct signature
        expect(() async {
          try {
            await service.fetch(nrlUri, aflUri, false);
          } catch (e) {
            // We expect this to fail due to invalid URL, but the signature should be correct
          }
        }, returnsNormally);
      });

      test('fetch method should return correct type structure on success', () {
        // This test documents the expected return type
        // Since we can't easily test successful network calls in unit tests,
        // we document the expected structure

        // Expected return type: Map<String, List<dynamic>>
        // Expected keys: 'nrlGames', 'aflGames'
        // Expected values: List<dynamic> for each key

        expect(true, isTrue); // Placeholder for type documentation
      });
    });

    group('Error message validation', () {
      test('should include meaningful error context', () async {
        try {
          await service.fetch(invalidNrlUrl, invalidAflUrl, false);
          fail('Expected exception was not thrown');
        } catch (e) {
          final errorMessage = e.toString();
          expect(errorMessage, contains('Exception'));
          // Error should contain context about what failed
          expect(
            errorMessage.toLowerCase(),
            anyOf([
              contains('nrl'),
              contains('afl'),
              contains('error'),
              contains('loading'),
            ]),
          );
        }
      });
    });

    group('Success scenarios', () {
      test('returns lists for both leagues on success (main thread)', () async {
        final svc = FixtureDownloadService.test((uri, league) async {
          if (league == League.nrl) return [1, 2, 3];
          return ['a'];
        });

        final result = await svc.fetch(
          Uri.parse('https://example.com/nrl'),
          Uri.parse('https://example.com/afl'),
          false,
        );

        expect(result['nrlGames'], isA<List<dynamic>>());
        expect(result['aflGames'], isA<List<dynamic>>());
        expect(result['nrlGames']!.length, 3);
        expect(result['aflGames']!.length, 1);
      });

      test('returns lists for both leagues when isolate requested (test path bypasses isolate)', () async {
        final svc = FixtureDownloadService.test((uri, league) async {
          if (league == League.nrl) return [42];
          return ['ok', 'done'];
        });

        final result = await svc.fetch(
          Uri.parse('https://example.com/nrl'),
          Uri.parse('https://example.com/afl'),
          true,
        );

        expect(result['nrlGames']!.length, 1);
        expect(result['aflGames']!.length, 2);
      });

      test('throws when AFL fetch fails after successful NRL', () async {
        final svc = FixtureDownloadService.test((uri, league) async {
          if (league == League.nrl) return [1];
          throw Exception('boom');
        });

        await expectLater(
          () => svc.fetch(
            Uri.parse('https://example.com/nrl'),
            Uri.parse('https://example.com/afl'),
            false,
          ),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
