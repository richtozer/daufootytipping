import 'dart:convert';

import 'package:daufootytipping/services/percent_stats_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(PercentStatsDiagnostics.resetForTest);

  test('report includes global and matching-game events only', () {
    PercentStatsDiagnostics.record(
      'bulk-listener.event',
      details: const <String, Object?>{'bulkMapKeyCount': 24},
    );
    PercentStatsDiagnostics.record(
      'direct-read.snapshot',
      gameKey: 'nrl-01-001',
      details: const <String, Object?>{'snapshotExists': false},
    );
    PercentStatsDiagnostics.record(
      'direct-read.snapshot',
      gameKey: 'nrl-01-002',
      details: const <String, Object?>{'snapshotExists': true},
    );

    final decoded = jsonDecode(
      PercentStatsDiagnostics.buildReport(
        gameKey: 'nrl-01-001',
        currentState: const <String, Object?>{
          'bulkMapContainsKey': false,
        },
      ),
    ) as Map<String, dynamic>;
    final events = decoded['events'] as List<dynamic>;

    expect(decoded['diagnostic'], 'percent-stats-v1');
    expect(decoded['currentState']['bulkMapContainsKey'], isFalse);
    expect(decoded['targetGameKey']['codeUnits'], <int>[
      110,
      114,
      108,
      45,
      48,
      49,
      45,
      48,
      48,
      49,
    ]);
    expect(events, hasLength(2));
    expect(events.map((event) => event['stage']), <String>[
      'bulk-listener.event',
      'direct-read.snapshot',
    ]);
    expect(
      events.any(
        (event) => event['gameKey']?['text'] == 'nrl-01-002',
      ),
      isFalse,
    );
  });

  test('event and tracked-key buffers stay bounded', () {
    for (var index = 0;
        index < PercentStatsDiagnostics.maximumEventsForTest + 3;
        index++) {
      PercentStatsDiagnostics.record(
        'event-$index',
        gameKey: 'nrl-01-${index.toString().padLeft(3, '0')}',
      );
    }

    expect(
      PercentStatsDiagnostics.eventsForTest,
      hasLength(PercentStatsDiagnostics.maximumEventsForTest),
    );
    expect(
      PercentStatsDiagnostics.eventsForTest.first['sequence'],
      4,
    );
    expect(PercentStatsDiagnostics.trackedGameKeys, hasLength(32));
  });

  test('near matches prioritize the same league and round', () {
    final matches = PercentStatsDiagnostics.nearMatchingKeyFingerprints(
      'nrl-03-017',
      const <String>[
        'afl-03-001',
        'nrl-02-009',
        'nrl-03-018',
        'nrl-03-016',
      ],
      limit: 3,
    );

    expect(
      matches.map((match) => match['text']),
      <String>['nrl-03-016', 'nrl-03-018', 'nrl-02-009'],
    );
  });
}
