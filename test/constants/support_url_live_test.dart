@Tags(['network'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:test/test.dart';

/// Checks the deployed support site is reachable at [p.supportUrl].
///
/// This hits the real network. Skip it offline with
/// `flutter test --exclude-tags network`.
void main() {
  late HttpClient client;

  setUp(() {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  });

  tearDown(() {
    client.close(force: true);
  });

  Future<HttpClientResponse> get(String path) async {
    final request = await client.getUrl(Uri.parse('${p.supportUrl}$path'));
    request.followRedirects = false;
    return request.close();
  }

  test('support page loads with the privacy policy', () async {
    final response = await get('/');
    final body = await response.transform(utf8.decoder).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(body, contains('DAU Footy Tipping'));
    expect(body, contains('id="privacy-policy"'));
    expect(body, contains('daufootytipping@gmail.com'));
  });

  test('/privacy-policy redirects to the privacy section', () async {
    final response = await get('/privacy-policy');
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.movedPermanently);
    expect(
      response.headers.value(HttpHeaders.locationHeader),
      endsWith('/#privacy-policy'),
    );
  });
}
