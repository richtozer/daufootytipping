import 'dart:async';

abstract class TimerScheduler {
  Timer schedulePeriodic(Duration duration, void Function(Timer) callback);
}

class TimerSchedulerDefault implements TimerScheduler {
  const TimerSchedulerDefault();

  @override
  Timer schedulePeriodic(Duration duration, void Function(Timer) callback) {
    return Timer.periodic(duration, callback);
  }
}

