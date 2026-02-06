import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/fixture_update_policy.dart';

void main() {
  group('FixtureUpdatePolicy.shouldStartDailyTimer', () {
    test('only starts for non-web, non-admin mode, admin role', () {
      const policy = FixtureUpdatePolicy();

      expect(
        policy.shouldStartDailyTimer(
          isWeb: false,
          isAdminMode: false,
          authenticatedRole: TipperRole.admin,
        ),
        isTrue,
      );

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

      expect(
        policy.shouldStartDailyTimer(
          isWeb: false,
          isAdminMode: false,
          authenticatedRole: TipperRole.tipper,
        ),
        isFalse,
      );
    });
  });

  group('FixtureUpdatePolicy.shouldTriggerFixtureUpdate', () {
    DAUComp comp() => DAUComp(
          dbkey: 'c',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: const [],
        );

    test('requires comp and last update; respects threshold by hours', () {
      const policy = FixtureUpdatePolicy();
      final now = DateTime.now().toUtc();

      // No comp
      expect(
        policy.shouldTriggerFixtureUpdate(activeComp: null, now: now, threshold: const Duration(hours: 24)),
        isFalse,
      );

      // No last update
      final c1 = comp();
      expect(
        policy.shouldTriggerFixtureUpdate(activeComp: c1, now: now, threshold: const Duration(hours: 24)),
        isFalse,
      );

      // 23 hours < 24 threshold
      final c2 = comp()..lastFixtureUpdateTimestampUTC = now.subtract(const Duration(hours: 23));
      expect(
        policy.shouldTriggerFixtureUpdate(activeComp: c2, now: now, threshold: const Duration(hours: 24)),
        isFalse,
      );

      // 24 hours >= 24 threshold
      final c3 = comp()..lastFixtureUpdateTimestampUTC = now.subtract(const Duration(hours: 24));
      expect(
        policy.shouldTriggerFixtureUpdate(activeComp: c3, now: now, threshold: const Duration(hours: 24)),
        isTrue,
      );
    });
  });
}

