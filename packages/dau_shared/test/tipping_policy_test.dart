import 'package:dau_shared/services/tipping_policy.dart';
import 'package:test/test.dart';

void main() {
  group('parseTipGracePeriodSeconds', () {
    test('uses the default when the setting is absent or not valid', () {
      for (final Object? value in <Object?>[
        null,
        '120',
        -1,
        0.5,
        double.infinity,
        double.nan,
        maxTipGracePeriodSeconds + 1,
        86400,
      ]) {
        expect(
          parseTipGracePeriodSeconds(value),
          defaultTipGracePeriodSeconds,
          reason: '$value',
        );
      }
    });

    test('accepts whole seconds from zero to the limit', () {
      expect(parseTipGracePeriodSeconds(0), 0);
      expect(parseTipGracePeriodSeconds(300), 300);
      expect(parseTipGracePeriodSeconds(300.0), 300);
      expect(
        parseTipGracePeriodSeconds(maxTipGracePeriodSeconds),
        maxTipGracePeriodSeconds,
      );
    });
  });

  group('tippingHasClosed', () {
    final DateTime kickoff = DateTime.utc(2027, 3, 1, 10);

    test('closes exactly at kickoff plus the grace period', () {
      expect(tippingHasClosed(kickoff, kickoff, 120), isFalse);
      expect(
        tippingHasClosed(
          kickoff,
          kickoff.add(const Duration(seconds: 119)),
          120,
        ),
        isFalse,
      );
      expect(
        tippingHasClosed(
          kickoff,
          kickoff.add(const Duration(seconds: 120)),
          120,
        ),
        isTrue,
      );
    });

    test('with no grace it closes at kickoff', () {
      expect(tippingHasClosed(kickoff, kickoff, 0), isTrue);
      expect(
        tippingHasClosed(
          kickoff,
          kickoff.subtract(const Duration(seconds: 1)),
          0,
        ),
        isFalse,
      );
    });
  });
}
