import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:dio/dio.dart';
import 'package:daufootytipping/services/url_health_checker.dart';

class MockDio extends Mock implements Dio {}
class MockResponse extends Mock implements Response {}

void main() {
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
  });
}

