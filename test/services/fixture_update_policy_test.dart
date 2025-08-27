import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/fixture_update_policy.dart';

void main() {
  group('FixtureUpdatePolicy', () {
    final policy = FixtureUpdatePolicy();

    test('shouldStartDailyTimer false on web or non-admin or admin mode', () {
      expect(
        policy.shouldStartDailyTimer(
          isWeb: true,
          isAdminMode: false,
          authenticatedRole: TipperRole.admin,
        ),
        isFalse,
      );
      expect(
        policy.shouldStartDailyTimer(
          isWeb: false,
          isAdminMode: true,
          authenticatedRole: TipperRole.admin,
        ),
        isFalse,
      );
      // Non-admin role should not start
      for (final role in TipperRole.values.where((r) => r != TipperRole.admin)) {
        expect(
          policy.shouldStartDailyTimer(
            isWeb: false,
            isAdminMode: false,
            authenticatedRole: role,
          ),
          isFalse,
        );
      }
      expect(
        policy.shouldStartDailyTimer(
          isWeb: false,
          isAdminMode: false,
          authenticatedRole: TipperRole.admin,
        ),
        isTrue,
      );
    });

    test('shouldTriggerFixtureUpdate respects threshold and last timestamp', () {
      final comp = DAUComp(
        dbkey: 'c',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: <DAURound>[],
        lastFixtureUpdateTimestampUTC: DateTime.parse('2025-01-01T00:00:00Z'),
      );
      final now = DateTime.parse('2025-01-02T00:00:01Z');
      expect(
        policy.shouldTriggerFixtureUpdate(
          activeComp: comp,
          now: now,
          threshold: const Duration(hours: 24),
        ),
        isTrue,
      );
      expect(
        policy.shouldTriggerFixtureUpdate(
          activeComp: comp,
          now: DateTime.parse('2025-01-01T23:00:00Z'),
          threshold: const Duration(hours: 24),
        ),
        isFalse,
      );
    });
  });
}
