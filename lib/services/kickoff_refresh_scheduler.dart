import 'dart:async';

typedef KickoffTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

class KickoffRefreshScheduler {
  KickoffRefreshScheduler({
    DateTime Function()? now,
    KickoffTimerFactory? createTimer,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _createTimer = createTimer ?? ((delay, callback) => Timer(delay, callback));

  final DateTime Function() _now;
  final KickoffTimerFactory _createTimer;
  Timer? _timer;

  void schedule({
    required Iterable<DateTime> Function() kickoffTimes,
    required void Function() onRefresh,
  }) {
    _timer?.cancel();
    _timer = null;

    final now = _now();
    DateTime? nextKickoff;
    for (final kickoff in kickoffTimes()) {
      if (kickoff.isAfter(now) &&
          (nextKickoff == null || kickoff.isBefore(nextKickoff))) {
        nextKickoff = kickoff;
      }
    }
    if (nextKickoff == null) {
      return;
    }

    _timer = _createTimer(nextKickoff.difference(now), () {
      _timer = null;
      onRefresh();
      schedule(kickoffTimes: kickoffTimes, onRefresh: onRefresh);
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
