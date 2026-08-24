import 'dart:async';

import 'package:daufootytipping/services/app_resume_data_refresher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconnects Android before refreshing fixtures', () async {
    final calls = <String>[];
    final refresher = AppResumeDataRefresher(
      platform: TargetPlatform.android,
      reconnectRealtimeDatabase: () async {
        calls.add('reconnect');
      },
      refreshFixtureData: () async {
        calls.add('fixtures');
      },
    );

    await refresher.refresh();

    expect(calls, <String>['reconnect', 'fixtures']);
  });

  test('does not reconnect non-Android platforms', () async {
    final calls = <String>[];
    final refresher = AppResumeDataRefresher(
      platform: TargetPlatform.iOS,
      reconnectRealtimeDatabase: () async {
        calls.add('reconnect');
      },
      refreshFixtureData: () async {
        calls.add('fixtures');
      },
    );

    await refresher.refresh();

    expect(calls, <String>['fixtures']);
  });

  test('still refreshes fixtures when Android reconnect fails', () async {
    final calls = <String>[];
    final reconnectErrors = <Object>[];
    final refresher = AppResumeDataRefresher(
      platform: TargetPlatform.android,
      reconnectRealtimeDatabase: () async {
        calls.add('reconnect');
        throw StateError('reconnect failed');
      },
      refreshFixtureData: () async {
        calls.add('fixtures');
      },
      onReconnectError: (error, _) => reconnectErrors.add(error),
    );

    await refresher.refresh();

    expect(calls, <String>['reconnect', 'fixtures']);
    expect(reconnectErrors.single, isA<StateError>());
  });

  test('retries Android reconnect independently of fixture refresh', () async {
    final calls = <String>[];
    var reconnectAttempts = 0;
    final refresher = AppResumeDataRefresher(
      platform: TargetPlatform.android,
      reconnectRealtimeDatabase: () async {
        reconnectAttempts++;
        calls.add('reconnect');
        if (reconnectAttempts < 3) {
          throw StateError('reconnect failed');
        }
      },
      refreshFixtureData: () async {
        calls.add('fixtures');
      },
      reconnectRetryDelays: const [Duration.zero, Duration.zero],
    );

    await refresher.refresh();

    expect(
      calls,
      <String>['reconnect', 'reconnect', 'reconnect', 'fixtures'],
    );
  });

  test('allows fixture failures to reach the coordinator retry policy', () async {
    final refresher = AppResumeDataRefresher(
      platform: TargetPlatform.iOS,
      reconnectRealtimeDatabase: () async {},
      refreshFixtureData: () async {
        throw TimeoutException('fixture refresh failed');
      },
    );

    await expectLater(
      refresher.refresh(),
      throwsA(isA<TimeoutException>()),
    );
  });
}
