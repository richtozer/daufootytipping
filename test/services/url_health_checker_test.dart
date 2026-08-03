import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:dio/dio.dart';
import 'package:daufootytipping/services/url_health_checker.dart';

class MockDio extends Mock implements Dio {}
class MockResponse extends Mock implements Response {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com/fallback'));
  });

  group('UrlHealthChecker', () {
    late MockDio dio;
    late UrlHealthChecker checker;

    setUp(() {
      dio = MockDio();
      checker = UrlHealthChecker(dio: dio);
    });

    test('returns true for 200 responses', () async {
      final uri = Uri.parse('https://example.com');
      final resp = Response(requestOptions: RequestOptions(path: uri.toString()), statusCode: 200);
      when(() => dio.getUri(uri)).thenAnswer((_) async => resp);
      expect(await checker.isActive(uri), isTrue);
    });

    test('returns false for non-200 status', () async {
      final uri = Uri.parse('https://example.com');
      final resp = Response(requestOptions: RequestOptions(path: uri.toString()), statusCode: 404);
      when(() => dio.getUri(uri)).thenAnswer((_) async => resp);
      expect(await checker.isActive(uri), isFalse);
    });

    test('returns false on exception', () async {
      final uri = Uri.parse('https://example.com');
      when(() => dio.getUri(uri)).thenThrow(Exception('network error'));
      expect(await checker.isActive(uri), isFalse);
    });

    test('accepts an unchanged URL without making a network request', () async {
      final uri = Uri.parse('https://example.com');

      expect(await checker.isActiveIfChanged(uri, previousUri: uri), isTrue);

      verifyNever(() => dio.getUri(any()));
    });

    test('checks a changed URL', () async {
      final previousUri = Uri.parse('https://example.com/old');
      final uri = Uri.parse('https://example.com/new');
      final resp = Response(
        requestOptions: RequestOptions(path: uri.toString()),
        statusCode: 200,
      );
      when(() => dio.getUri(uri)).thenAnswer((_) async => resp);

      expect(
        await checker.isActiveIfChanged(uri, previousUri: previousUri),
        isTrue,
      );
      verify(() => dio.getUri(uri)).called(1);
    });

    test(
      'uses the remote checker result without hitting dio directly',
      () async {
        final remoteChecker = UrlHealthChecker(
          dio: dio,
          remoteChecker: (_) async => true,
        );
        final uri = Uri.parse('https://example.com');

        expect(await remoteChecker.isActive(uri), isTrue);

        verifyNever(() => dio.getUri(any()));
      },
    );

    test(
      'falls back to a direct check when the remote checker throws',
      () async {
        final uri = Uri.parse('https://example.com');
        final resp = Response(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
        );
        when(() => dio.getUri(uri)).thenAnswer((_) async => resp);
        final remoteChecker = UrlHealthChecker(
          dio: dio,
          remoteChecker: (_) async => throw Exception('cloud function down'),
        );

        expect(await remoteChecker.isActive(uri), isTrue);

        verify(() => dio.getUri(uri)).called(1);
      },
    );

    test(
      'propagates the remote checker failure instead of falling back when direct fallback is disallowed',
      () async {
        final uri = Uri.parse('https://example.com');
        final remoteChecker = UrlHealthChecker(
          dio: dio,
          remoteChecker: (_) async => throw Exception('cloud function down'),
          allowDirectFallback: false,
        );

        await expectLater(remoteChecker.isActive(uri), throwsException);

        verifyNever(() => dio.getUri(any()));
      },
    );

    test(
      'uses the remote checker result without a direct check when fallback is disallowed',
      () async {
        final uri = Uri.parse('https://example.com');
        final remoteChecker = UrlHealthChecker(
          dio: dio,
          remoteChecker: (_) async => true,
          allowDirectFallback: false,
        );

        expect(await remoteChecker.isActive(uri), isTrue);

        verifyNever(() => dio.getUri(any()));
      },
    );
  });
}
