import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('app badge count endpoint is publicly invokable', () {
    final manifest = File('functions.yaml').readAsStringSync();
    final appBadgeEndpoint = RegExp(
      r'^  app-badge-count:\n(?:(?!^  \S).*(?:\n|$))*',
      multiLine: true,
    ).firstMatch(manifest)?.group(0);

    expect(appBadgeEndpoint, isNotNull);
    expect(appBadgeEndpoint, contains('invoker:\n        - public'));
  });
}
