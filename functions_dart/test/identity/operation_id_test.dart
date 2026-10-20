import 'dart:math';

import 'package:dart_functions/identity/operation_id.dart';
import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('newOperationId', () {
    test('is 32 hex characters and a valid database key without a bar', () {
      final id = newOperationId();

      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(isValidRtdbKey(id), isTrue);
      expect(id, isNot(contains('|')));
    });

    test('does not repeat across many calls', () {
      final ids = {
        for (var index = 0; index < 10000; index++) newOperationId(),
      };

      expect(ids, hasLength(10000));
    });

    test('is deterministic for a seeded random source, for tests only', () {
      expect(
        newOperationId(random: Random(7)),
        newOperationId(random: Random(7)),
      );
    });
  });
}
