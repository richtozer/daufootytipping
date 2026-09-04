import 'dart:io';

import 'package:dau_shared/constants/function_endpoints.dart';
import 'package:test/test.dart';

/// Extracts a single endpoint block from the generated manifest.
String? _endpointBlock(String manifest, String id) => RegExp(
  '^  ${RegExp.escape(id)}:\n(?:(?!^  \\S).*(?:\n|\$))*',
  multiLine: true,
).firstMatch(manifest)?.group(0);

void main() {
  final manifest = File('functions.yaml').readAsStringSync();

  // The endpoint ids are the deployed Cloud Run service names, hardcoded in the
  // Flutter client and the TypeScript wrappers. firebase_functions 0.7 derives
  // them from the `name:` argument, so a rename there silently renames a
  // production function. Asserting the generated manifest against the shared
  // constants makes that a test failure instead.
  const callableEndpoints = <String>[
    adminFixtureDownloadEndpoint,
    adminScoringRescoreEndpoint,
    adminCheckFixtureUrlEndpoint,
  ];
  const httpsEndpoints = <String>[
    backendScoringCommandEndpoint,
    scheduledFixtureDownloadEndpoint,
    appBadgeCountEndpoint,
  ];

  group('deployment manifest', () {
    for (final id in [...callableEndpoints, ...httpsEndpoints]) {
      test('$id is present with the expected id, entryPoint and region', () {
        final block = _endpointBlock(manifest, id);
        expect(
          block,
          isNotNull,
          reason:
              'Endpoint "$id" is missing from functions.yaml. If a `name:` in '
              'bin/server.dart changed, this renames a deployed function and '
              'breaks the Flutter client and the TypeScript wrappers.',
        );
        expect(block, contains('entryPoint: $id'));
        expect(block, contains('region:\n      - asia-southeast1'));
        expect(block, contains('platform: gcfv2'));
      });
    }

    for (final id in callableEndpoints) {
      test('$id is a callable trigger', () {
        expect(_endpointBlock(manifest, id), contains('callableTrigger:'));
      });
    }

    for (final id in httpsEndpoints) {
      test('$id is an https trigger', () {
        expect(_endpointBlock(manifest, id), contains('httpsTrigger:'));
      });
    }

    test('$appBadgeCountEndpoint is publicly invokable', () {
      expect(
        _endpointBlock(manifest, appBadgeCountEndpoint),
        contains('invoker:\n        - public'),
      );
    });

    test('no unexpected endpoints are declared', () {
      final declared = RegExp(r'^  (\S+):', multiLine: true)
          .allMatches(manifest)
          .map((m) => m.group(1)!)
          .where((id) => id != 'api' && id != 'reason')
          .toSet();
      expect(declared, {...callableEndpoints, ...httpsEndpoints});
    });
  });
}
