import 'dart:io';

import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:test/test.dart';

/// Offline checks that the in-app support link, and the site it points to,
/// stay consistent. The live check is in `support_url_live_test.dart`.
void main() {
  group('supportUrl', () {
    test('is an https origin with no path or trailing slash', () {
      final uri = Uri.parse(p.supportUrl);

      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, isEmpty);
    });

    test('is the only support link hard-coded in the app', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final offenders = <String>[
        for (final file in dartFiles)
          if (file.readAsStringSync().contains('interview.coach/tipping'))
            file.path,
      ];

      expect(
        offenders,
        isEmpty,
        reason: 'Use p.supportUrl instead of the old support page link.',
      );
    });
  });

  group('support_site', () {
    final indexHtml = File('support_site/index.html').readAsStringSync();
    final redirects = File('support_site/_redirects').readAsStringSync();

    test('has the privacy policy section the store listings link to', () {
      expect(indexHtml, contains('id="privacy-policy"'));
      expect(
        redirects,
        matches(
          RegExp(
            r'^/privacy-policy\s+/#privacy-policy\s+301$',
            multiLine: true,
          ),
        ),
      );
    });

    test('keeps the old /tipping path working', () {
      expect(
        redirects,
        matches(RegExp(r'^/tipping\s+/\s+301$', multiLine: true)),
      );
    });

    test('gives one contact address for support and privacy', () {
      final emails = RegExp(r'mailto:([^"]+)')
          .allMatches(indexHtml)
          .map((match) => match.group(1))
          .toSet();

      expect(emails, {'daufootytipping@gmail.com'});
    });
  });
}
