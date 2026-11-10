import 'dart:async';

import 'package:daufootytipping/services/server_clock.dart';
import 'package:daufootytipping/services/tipping_deadline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart';

void main() {
  tearDown(() async {
    await di.reset();
  });

  test(
    'absent, invalid and excessive grace use two minutes; zero disables it',
    () {
      for (final value in [
        null,
        '120',
        -1,
        0.5,
        double.infinity,
        maxTipGracePeriodSeconds + 1,
      ]) {
        expect(parseTipGracePeriodSeconds(value), 120);
      }
      expect(parseTipGracePeriodSeconds(0), 0);
      expect(parseTipGracePeriodSeconds(300), 300);
    },
  );

  test('tipping closes exactly at kickoff plus the configured grace', () {
    final kickoff = DateTime.utc(2027, 3, 1, 10);
    expect(tippingIsOpen(kickoff, now: kickoff), isTrue);
    expect(
      tippingIsOpen(kickoff, now: kickoff.add(const Duration(seconds: 119))),
      isTrue,
    );
    expect(
      tippingIsOpen(kickoff, now: kickoff.add(const Duration(seconds: 120))),
      isFalse,
    );
    expect(tippingIsOpen(kickoff, now: kickoff, graceSeconds: 0), isFalse);
    expect(
      tippingIsOpen(
        kickoff,
        now: kickoff.add(const Duration(seconds: 150)),
        graceSeconds: 300,
      ),
      isTrue,
    );
  });

  group('judged by the server clock', () {
    Future<ServerClock> clockAhead(Duration offset) async {
      final clock = ServerClock(Stream<Duration>.value(offset));
      di.registerSingleton<ServerClock>(clock);
      await Future<void>.delayed(Duration.zero);
      return clock;
    }

    test('a phone whose clock is fast is not shut out early', () async {
      // The phone reads 150 s past kickoff, but it is 90 s fast: the server reads
      // 60 s past kickoff, with 60 s of the 120 s grace left to run.
      final DateTime kickoff = DateTime.now().toUtc().subtract(
        const Duration(seconds: 150),
      );
      expect(
        tippingIsOpen(kickoff),
        isFalse,
        reason: 'by the phone alone: closed',
      );

      await clockAhead(const Duration(seconds: -90));

      expect(
        tippingIsOpen(kickoff),
        isTrue,
        reason: 'by the server: still open',
      );
    });

    test(
      'a phone whose clock is slow is not shown a closed game as open',
      () async {
        // The phone reads 70 s past kickoff, but it is 60 s slow: the server reads
        // 130 s past kickoff, and has already closed.
        final DateTime kickoff = DateTime.now().toUtc().subtract(
          const Duration(seconds: 70),
        );
        expect(
          tippingIsOpen(kickoff),
          isTrue,
          reason: 'by the phone alone: open',
        );

        await clockAhead(const Duration(seconds: 60));

        expect(
          tippingIsOpen(kickoff),
          isFalse,
          reason: 'by the server: closed',
        );
      },
    );

    test('the offset is followed as the database reports it', () async {
      final offsets = StreamController<Duration>();
      final clock = ServerClock(offsets.stream);
      addTearDown(() async {
        await clock.dispose();
        await offsets.close();
      });
      expect(clock.offset, Duration.zero);

      offsets.add(const Duration(milliseconds: 1500));
      await Future<void>.delayed(Duration.zero);

      expect(clock.offset, const Duration(milliseconds: 1500));
      final Duration drift =
          clock.now().difference(DateTime.now()) -
          const Duration(milliseconds: 1500);
      expect(drift.abs(), lessThan(const Duration(seconds: 1)));
    });
  });
}
