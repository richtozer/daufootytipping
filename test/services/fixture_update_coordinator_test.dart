import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/fixture_update_coordinator.dart';

void main() {
  group('FixtureUpdateCoordinator', () {
    DAUComp comp({DateTime? last}) => DAUComp(
          dbkey: 'c',
          name: 'Comp',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: const [],
        )..lastFixtureUpdateTimestampUTC = last;

    test('shouldStartDailyTimer delegates policy correctly', () {
      final c = FixtureUpdateCoordinator();
      expect(
        c.shouldStartDailyTimer(isWeb: false, isAdminMode: false, authenticatedRole: TipperRole.admin),
        isTrue,
      );
      expect(
        c.shouldStartDailyTimer(isWeb: true, isAdminMode: false, authenticatedRole: TipperRole.admin),
        isFalse,
      );
      expect(
        c.shouldStartDailyTimer(isWeb: false, isAdminMode: true, authenticatedRole: TipperRole.admin),
        isFalse,
      );
    });

    test('maybeTriggerUpdate skips when conditions not met and triggers when met', () async {
      // Freeze time via custom coordinator now()
      final now = DateTime.parse('2025-01-10T00:00:00Z');
      final c = FixtureUpdateCoordinator(now: () => now);

      // 1) No active comp => false
      final r1 = await c.maybeTriggerUpdate(
        activeComp: null,
        selectedComp: null,
        threshold: const Duration(hours: 24),
        isSelectedCompActive: () => false,
        isCompOver: (comp) => false,
        refreshActiveByKey: (key) async => null,
        logAnalytics: (name, params) async {},
        runFixtureUpdate: (comp) async => 'no-op',
        afterUpdate: () async {},
      );
      expect(r1, isFalse);

      // 2) Active but below threshold => false
      final a2 = comp(last: now.subtract(const Duration(hours: 23)));
      final r2 = await c.maybeTriggerUpdate(
        activeComp: a2,
        selectedComp: a2,
        threshold: const Duration(hours: 24),
        isSelectedCompActive: () => true,
        isCompOver: (comp) => false,
        refreshActiveByKey: (key) async => a2,
        logAnalytics: (name, params) async {},
        runFixtureUpdate: (comp) async => 'no-op',
        afterUpdate: () async {},
      );
      expect(r2, isFalse);

      // 3) Threshold met but selected != active => false
      final a3 = comp(last: now.subtract(const Duration(hours: 24)));
      final r3 = await c.maybeTriggerUpdate(
        activeComp: a3,
        selectedComp: null,
        threshold: const Duration(hours: 24),
        isSelectedCompActive: () => false,
        isCompOver: (comp) => false,
        refreshActiveByKey: (key) async => a3,
        logAnalytics: (name, params) async {},
        runFixtureUpdate: (comp) async => 'no-op',
        afterUpdate: () async {},
      );
      expect(r3, isFalse);

      // 4) Threshold met and selected==active but comp over => false
      final a4 = comp(last: now.subtract(const Duration(hours: 24)));
      final r4 = await c.maybeTriggerUpdate(
        activeComp: a4,
        selectedComp: a4,
        threshold: const Duration(hours: 24),
        isSelectedCompActive: () => true,
        isCompOver: (comp) => true,
        refreshActiveByKey: (key) async => a4,
        logAnalytics: (name, params) async {},
        runFixtureUpdate: (comp) async => 'no-op',
        afterUpdate: () async {},
      );
      expect(r4, isFalse);

      // 5) All conditions met => true; analytics, update, afterUpdate called
      int analytics = 0;
      int updates = 0;
      int afters = 0;
      final a5 = comp(last: now.subtract(const Duration(hours: 24)));
      final r5 = await c.maybeTriggerUpdate(
        activeComp: a5,
        selectedComp: a5,
        threshold: const Duration(hours: 24),
        isSelectedCompActive: () => true,
        isCompOver: (comp) => false,
        refreshActiveByKey: (key) async => a5,
        logAnalytics: (name, params) async => analytics++,
        runFixtureUpdate: (comp) async {
          updates++;
          return 'ok';
        },
        afterUpdate: () async => afters++,
      );
      expect(r5, isTrue);
      expect(analytics, 1);
      expect(updates, 1);
      expect(afters, 1);
    });
  });
}
