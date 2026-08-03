import 'dart:async';

import 'package:daufootytipping/services/kickoff_refresh_scheduler.dart';
import 'package:test/test.dart';

void main() {
  group('KickoffRefreshScheduler', () {
    late DateTime now;
    late List<_ScheduledTimer> timers;
    late KickoffRefreshScheduler scheduler;

    setUp(() {
      now = DateTime.utc(2030, 1, 1, 12);
      timers = <_ScheduledTimer>[];
      scheduler = KickoffRefreshScheduler(
        now: () => now,
        createTimer: (delay, callback) {
          final timer = _ScheduledTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
      );
    });

    tearDown(() {
      scheduler.dispose();
    });

    test('refreshes at the nearest kickoff and schedules the following game', () {
      final firstKickoff = now.add(const Duration(minutes: 30));
      final secondKickoff = now.add(const Duration(hours: 2));
      var refreshCount = 0;

      scheduler.schedule(
        kickoffTimes: () => <DateTime>[secondKickoff, firstKickoff],
        onRefresh: () => refreshCount++,
      );

      expect(timers.single.delay, const Duration(minutes: 30));

      now = firstKickoff;
      timers.single.fire();

      expect(refreshCount, 1);
      expect(timers.last.delay, const Duration(minutes: 90));
    });

    test('rescheduling and disposal cancel their active timers', () {
      scheduler.schedule(
        kickoffTimes: () => <DateTime>[now.add(const Duration(hours: 1))],
        onRefresh: () {},
      );
      final firstTimer = timers.single;

      scheduler.schedule(
        kickoffTimes: () => <DateTime>[now.add(const Duration(hours: 2))],
        onRefresh: () {},
      );
      final secondTimer = timers.last;

      expect(firstTimer.isActive, isFalse);
      scheduler.dispose();
      expect(secondTimer.isActive, isFalse);
    });
  });
}

class _ScheduledTimer implements Timer {
  _ScheduledTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _isActive = true;

  void fire() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _callback();
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;

  @override
  void cancel() {
    _isActive = false;
  }
}
