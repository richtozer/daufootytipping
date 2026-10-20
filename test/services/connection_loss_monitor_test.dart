import 'dart:async';

import 'package:daufootytipping/services/analytics_service.dart';
import 'package:daufootytipping/services/connection_loss_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAnalytics implements AnalyticsService {
  final List<({String name, Map<String, Object> parameters})> events = [];
  Object? failWith;

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name: name, parameters: parameters ?? const {}));
    final Object? failure = failWith;
    if (failure != null) {
      throw failure;
    }
  }
}

void main() {
  const Duration threshold = Duration(milliseconds: 60);
  const Duration beforeThreshold = Duration(milliseconds: 25);
  const Duration afterThreshold = Duration(milliseconds: 110);

  late StreamController<bool?> connection;
  late ConnectionLossMonitor monitor;
  late int notifications;

  setUp(() {
    connection = StreamController<bool?>.broadcast();
    monitor = ConnectionLossMonitor(
      connectionStates: connection.stream,
      threshold: threshold,
    );
    notifications = 0;
    monitor.addListener(() => notifications++);
  });

  tearDown(() async {
    monitor.dispose();
    await connection.close();
  });

  Future<void> pause(Duration duration) => Future<void>.delayed(duration);

  test('shows nothing while the connection is up', () async {
    connection.add(true);
    await pause(afterThreshold);

    expect(monitor.noticeVisible, isFalse);
  });

  test(
    'shows the notice once the connection has been down for the threshold',
    () async {
      connection.add(false);
      await pause(beforeThreshold);
      expect(monitor.noticeVisible, isFalse, reason: 'a short blip is normal');

      await pause(afterThreshold);
      expect(monitor.noticeVisible, isTrue);
      expect(notifications, 1);
    },
  );

  test('a connection that comes back in time never shows the notice', () async {
    connection.add(false);
    await pause(beforeThreshold);
    connection.add(true);
    await pause(afterThreshold);

    expect(monitor.noticeVisible, isFalse);
    expect(notifications, 0);
  });

  test('the notice goes away when the connection returns', () async {
    connection.add(false);
    await pause(afterThreshold);
    expect(monitor.noticeVisible, isTrue);

    connection.add(true);
    await pause(Duration.zero);

    expect(monitor.noticeVisible, isFalse);
  });

  test('a state not yet known counts as down', () async {
    connection.add(null);
    await pause(afterThreshold);

    expect(monitor.noticeVisible, isTrue);
  });

  test('before the first state arrives it also counts down', () async {
    await pause(afterThreshold);

    expect(monitor.noticeVisible, isTrue);
  });

  test('repeated down events do not restart the wait', () async {
    connection.add(false);
    await pause(beforeThreshold);
    connection.add(false);
    await pause(beforeThreshold);
    connection.add(false);
    await pause(beforeThreshold);

    expect(
      monitor.noticeVisible,
      isTrue,
      reason: 'the wait runs from the first down event',
    );
  });

  group('app in the background', () {
    test('being disconnected in the background is not an outage', () async {
      connection.add(true);
      monitor.setForeground(false);
      connection.add(false);
      await pause(afterThreshold);

      expect(monitor.noticeVisible, isFalse);
    });

    test('going to the background hides the notice', () async {
      connection.add(false);
      await pause(afterThreshold);
      expect(monitor.noticeVisible, isTrue);

      monitor.setForeground(false);

      expect(monitor.noticeVisible, isFalse);
    });

    test(
      'coming back still disconnected waits the full threshold again',
      () async {
        connection.add(false);
        await pause(afterThreshold);
        monitor.setForeground(false);

        monitor.setForeground(true);
        expect(monitor.noticeVisible, isFalse);
        await pause(beforeThreshold);
        expect(
          monitor.noticeVisible,
          isFalse,
          reason: 'the SDK normally reconnects within moments of a resume',
        );

        await pause(afterThreshold);
        expect(monitor.noticeVisible, isTrue);
      },
    );

    test('coming back already connected shows nothing', () async {
      connection.add(false);
      monitor.setForeground(false);
      connection.add(true);
      monitor.setForeground(true);
      await pause(afterThreshold);

      expect(monitor.noticeVisible, isFalse);
    });
  });

  group('dismissing', () {
    test('hides the notice for the rest of that outage', () async {
      connection.add(false);
      await pause(afterThreshold);

      monitor.dismiss();
      expect(monitor.noticeVisible, isFalse);

      connection.add(false);
      await pause(afterThreshold);
      expect(monitor.noticeVisible, isFalse);
    });

    test('a later outage shows the notice again', () async {
      connection.add(false);
      await pause(afterThreshold);
      monitor.dismiss();

      connection.add(true);
      await pause(Duration.zero);
      connection.add(false);
      await pause(afterThreshold);

      expect(monitor.noticeVisible, isTrue);
    });

    test('dismissing when nothing is shown changes nothing', () async {
      monitor.dismiss();

      expect(notifications, 0);
    });
  });

  group('reporting to analytics', () {
    late RecordingAnalytics analytics;
    late StreamController<bool?> own;
    late ConnectionLossMonitor reporting;
    late DateTime now;

    setUp(() {
      analytics = RecordingAnalytics();
      own = StreamController<bool?>.broadcast();
      now = DateTime.utc(2026, 10, 20, 12);
      reporting = ConnectionLossMonitor(
        connectionStates: own.stream,
        threshold: threshold,
        analytics: analytics,
        clock: () => now,
      );
    });

    tearDown(() async {
      reporting.dispose();
      await own.close();
    });

    test(
      'logs when the notice is shown and how long the outage had lasted',
      () async {
        own.add(false);
        now = now.add(const Duration(seconds: 31));
        await pause(afterThreshold);

        expect(analytics.events, hasLength(1));
        expect(analytics.events.single.name, 'connection_lost_notice_shown');
        expect(analytics.events.single.parameters, {'down_seconds': 31});
      },
    );

    test('logs nothing for a blip that recovers before the notice', () async {
      own.add(false);
      await pause(beforeThreshold);
      own.add(true);
      await pause(afterThreshold);

      expect(analytics.events, isEmpty);
    });

    test(
      'logs the recovery after a notice with the length of the outage',
      () async {
        own.add(false);
        await pause(afterThreshold);
        now = now.add(const Duration(seconds: 95));

        own.add(true);
        await pause(Duration.zero);

        expect(analytics.events.map((event) => event.name), [
          'connection_lost_notice_shown',
          'connection_restored_after_notice',
        ]);
        expect(analytics.events.last.parameters, {'outage_seconds': 95});
      },
    );

    test('logs a dismissal with how long the notice was on screen', () async {
      own.add(false);
      await pause(afterThreshold);
      now = now.add(const Duration(seconds: 12));

      reporting.dismiss();

      expect(analytics.events.last.name, 'connection_lost_notice_dismissed');
      expect(analytics.events.last.parameters, {'visible_seconds': 12});
    });

    test(
      'still logs the recovery when the notice had been dismissed',
      () async {
        own.add(false);
        await pause(afterThreshold);
        reporting.dismiss();
        own.add(true);
        await pause(Duration.zero);

        expect(analytics.events.map((event) => event.name), [
          'connection_lost_notice_shown',
          'connection_lost_notice_dismissed',
          'connection_restored_after_notice',
        ]);
      },
    );

    test('logs one recovery per outage and no second shown event while the notice stays up', () async {
      own.add(false);
      await pause(afterThreshold);
      own.add(false);
      own.add(null);
      await pause(afterThreshold);
      own.add(true);
      own.add(true);
      await pause(Duration.zero);

      expect(analytics.events.map((event) => event.name), [
        'connection_lost_notice_shown',
        'connection_restored_after_notice',
      ]);
    });

    test(
      'a trip to the background ends the outage without a recovery event',
      () async {
        own.add(false);
        await pause(afterThreshold);
        reporting.setForeground(false);
        own.add(true);
        reporting.setForeground(true);
        await pause(Duration.zero);

        expect(analytics.events.map((event) => event.name), [
          'connection_lost_notice_shown',
        ]);
      },
    );

    test('an analytics failure never disturbs the notice', () async {
      analytics.failWith = StateError('analytics unavailable');
      own.add(false);
      await pause(afterThreshold);

      expect(reporting.noticeVisible, isTrue);
      own.add(true);
      await pause(Duration.zero);
      expect(reporting.noticeVisible, isFalse);
    });

    test('event names are stable, since dashboards will key on them', () {
      expect(
        ConnectionLossMonitor.noticeShownEvent,
        'connection_lost_notice_shown',
      );
      expect(
        ConnectionLossMonitor.noticeDismissedEvent,
        'connection_lost_notice_dismissed',
      );
      expect(
        ConnectionLossMonitor.restoredEvent,
        'connection_restored_after_notice',
      );
    });
  });

  test('a monitor disposed mid-wait neither fires nor throws', () async {
    final StreamController<bool?> own = StreamController<bool?>.broadcast();
    final ConnectionLossMonitor disposed = ConnectionLossMonitor(
      connectionStates: own.stream,
      threshold: threshold,
    );
    own.add(false);
    disposed.dispose();

    // A notify after dispose would assert inside the timer and fail the test.
    await pause(afterThreshold);
    own.add(true);
    await pause(Duration.zero);

    expect(own.hasListener, isFalse, reason: 'it unsubscribed');
    await own.close();
  });
}
