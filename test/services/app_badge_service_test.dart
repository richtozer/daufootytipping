import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutstandingTipsAppBadgeController', () {
    late _RecordingBadgeWriter badgeWriter;
    late OutstandingTipsAppBadgeController controller;
    late DAUComp comp;

    setUp(() {
      badgeWriter = _RecordingBadgeWriter();
      controller = OutstandingTipsAppBadgeController(badgeWriter);
      comp = DAUComp(
        dbkey: 'comp',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://example.com/afl'),
        nrlFixtureJsonURL: Uri.parse('https://example.com/nrl'),
        daurounds: <DAURound>[],
      );
    });

    test('sets the count for a paid non-anonymous tipper', () async {
      await controller.sync(
        tipper: _tipper(compsPaidFor: <DAUComp>[comp]),
        comp: comp,
        outstandingCount: 4,
      );

      expect(badgeWriter.counts, <int>[4]);
    });

    test('clears the count for an unpaid tipper', () async {
      await controller.sync(
        tipper: _tipper(),
        comp: comp,
        outstandingCount: 4,
      );

      expect(badgeWriter.counts, <int>[0]);
    });

    test('clears the count for an anonymous tipper', () async {
      await controller.sync(
        tipper: _tipper(isAnonymous: true, compsPaidFor: <DAUComp>[comp]),
        comp: comp,
        outstandingCount: 4,
      );

      expect(badgeWriter.counts, <int>[0]);
    });

    test('clears the count when no competition is selected', () async {
      await controller.sync(
        tipper: _tipper(compsPaidFor: <DAUComp>[comp]),
        comp: null,
        outstandingCount: 4,
      );

      expect(badgeWriter.counts, <int>[0]);
    });

    test('does not write the same effective count more than once', () async {
      final tipper = _tipper(compsPaidFor: <DAUComp>[comp]);

      await controller.sync(tipper: tipper, comp: comp, outstandingCount: 4);
      await controller.sync(tipper: tipper, comp: comp, outstandingCount: 4);

      expect(badgeWriter.counts, <int>[4]);
    });

    test('logs a failed write and retries the same count', () async {
      final messages = <String>[];
      badgeWriter.result = false;
      controller = OutstandingTipsAppBadgeController(
        badgeWriter,
        logMessage: messages.add,
      );
      final tipper = _tipper(compsPaidFor: <DAUComp>[comp]);

      expect(
        await controller.sync(
          tipper: tipper,
          comp: comp,
          outstandingCount: 4,
        ),
        isFalse,
      );
      expect(
        await controller.sync(
          tipper: tipper,
          comp: comp,
          outstandingCount: 4,
        ),
        isFalse,
      );

      expect(badgeWriter.counts, <int>[4, 4]);
      expect(messages, <String>[
        'Could not update the app badge to 4',
        'Could not update the app badge to 4',
      ]);
    });
  });
}

Tipper _tipper({
  bool isAnonymous = false,
  List<DAUComp> compsPaidFor = const <DAUComp>[],
}) {
  return Tipper(
    dbkey: 'tipper',
    compsPaidFor: compsPaidFor,
    authuid: 'auth',
    email: 'tipper@example.com',
    name: 'Tipper',
    tipperRole: TipperRole.tipper,
    isAnonymous: isAnonymous,
  );
}

class _RecordingBadgeWriter implements BadgeCountWriter {
  final List<int> counts = <int>[];
  bool result = true;

  @override
  Future<bool> setCount(int count) async {
    counts.add(count);
    return result;
  }
}
