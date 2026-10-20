import 'dart:convert';
import 'dart:io';

import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('kickoffEpochMsFromDateUtc', () {
    test('reads the feed format as UTC milliseconds since the epoch', () {
      // Reference values computed independently with Node's Date.parse.
      expect(kickoffEpochMsFromDateUtc('2026-03-01 02:15:00Z'), 1772331300000);
      expect(kickoffEpochMsFromDateUtc('2025-03-02 00:00:00Z'), 1740873600000);
      expect(kickoffEpochMsFromDateUtc('2024-03-03 02:30:00Z'), 1709433000000);
      expect(kickoffEpochMsFromDateUtc('2026-10-19 16:59:58Z'), 1792429198000);
    });

    test('also reads the T form and milliseconds, as DateTime.parse does', () {
      expect(kickoffEpochMsFromDateUtc('2026-03-01T02:15:00Z'), 1772331300000);
      expect(
        kickoffEpochMsFromDateUtc('2026-03-01T02:15:00.250Z'),
        1772331300250,
      );
      expect(
        kickoffEpochMsFromDateUtc('2026-03-01 02:15:00.5Z'),
        1772331300500,
      );
      expect(
        kickoffEpochMsFromDateUtc('2025-01-01T00:00:00Z'),
        DateTime.parse('2025-01-01T00:00:00Z').millisecondsSinceEpoch,
      );
    });

    test('is not shifted by the time zone the code runs in', () {
      // The same wall clock time a day apart is exactly 24 hours apart, even
      // across a daylight saving change in the host's own zone.
      final first = kickoffEpochMsFromDateUtc('2026-04-04 15:00:00Z');
      final second = kickoffEpochMsFromDateUtc('2026-04-05 15:00:00Z');

      expect(second - first, const Duration(hours: 24).inMilliseconds);
    });

    test('refuses anything that is not exactly the stored format', () {
      for (final value in [
        '',
        'tomorrow',
        '2026-03-01',
        '2026-03-01 02:15:00', // no Z: not stated as UTC
        '2026-03-01T02:15:00', // likewise
        '2026-03-01 02:15:00+11:00', // another offset
        '2026-03-01 02:15:00.1234Z', // finer than milliseconds
        '2026-13-01 02:15:00Z', // no such month
        '2026-02-30 02:15:00Z', // no such day
        '2026-03-01 25:15:00Z',
      ]) {
        expect(
          () => kickoffEpochMsFromDateUtc(value),
          throwsFormatException,
          reason: 'value: "$value"',
        );
      }
    });
  });

  group('shared vectors (also asserted by the Node backfill script)', () {
    final vectors =
        jsonDecode(File('../../config/kickoff-vectors.json').readAsStringSync())
            as Map<String, Object?>;

    test('every valid string gives the same milliseconds as Node', () {
      final valid = (vectors['valid']! as List).cast<Map<String, Object?>>();
      expect(valid, isNotEmpty);
      for (final vector in valid) {
        expect(
          kickoffEpochMsFromDateUtc(vector['input']! as String),
          vector['epochMs'],
          reason: 'input: ${vector['input']}',
        );
      }
    });

    test('every invalid string is refused, as in Node', () {
      final invalid = (vectors['invalid']! as List).cast<String>();
      expect(invalid, isNotEmpty);
      for (final value in invalid) {
        expect(
          () => kickoffEpochMsFromDateUtc(value),
          throwsFormatException,
          reason: 'input: "$value"',
        );
      }
    });
  });

  group('dateUtcFromDateTime', () {
    test('writes the stored format and round trips with the parser', () {
      final kickoff = DateTime.utc(2026, 3, 1, 2, 15);

      expect(dateUtcFromDateTime(kickoff), '2026-03-01 02:15:00Z');
      expect(
        kickoffEpochMsFromDateUtc(dateUtcFromDateTime(kickoff)),
        kickoff.millisecondsSinceEpoch,
      );
    });

    test('pads every field', () {
      expect(
        dateUtcFromDateTime(DateTime.utc(2026, 1, 2, 3, 4, 5)),
        '2026-01-02 03:04:05Z',
      );
    });
  });

  group('FixtureImportApplier writes the numeric kickoff beside DateUtc', () {
    const applier = FixtureImportApplier();

    Map<String, dynamic> feedGame({
      Object? dateUtc = '2026-03-01 02:15:00Z',
      int round = 1,
      int match = 1,
    }) {
      return <String, dynamic>{
        'RoundNumber': round,
        'MatchNumber': match,
        'HomeTeam': 'Knights',
        'AwayTeam': 'Cowboys',
        'Location': 'Allegiant Stadium',
        'DateUtc': ?dateUtc,
        'HomeTeamScore': null,
        'AwayTeamScore': null,
      };
    }

    test('adds DateUtcEpochMs in the same attribute set as DateUtc', () {
      final updates = applier.buildGameUpdates([feedGame()], const []);

      expect(updates, hasLength(1));
      expect(updates.single.attributes['DateUtc'], '2026-03-01 02:15:00Z');
      expect(updates.single.attributes['DateUtcEpochMs'], 1772331300000);
    });

    test('the epoch always agrees with the DateUtc beside it', () {
      final updates = applier.buildGameUpdates(
        [
          feedGame(dateUtc: '2026-03-01 02:15:00Z', match: 1),
          feedGame(dateUtc: '2026-03-01 04:30:00Z', match: 2),
          feedGame(dateUtc: '2026-03-05 08:30:00Z', round: 2, match: 3),
        ],
        [feedGame(dateUtc: '2026-03-05 08:30:00Z', match: 1)],
      );

      for (final update in updates) {
        expect(
          update.attributes['DateUtcEpochMs'],
          kickoffEpochMsFromDateUtc(update.attributes['DateUtc'] as String),
        );
      }
    });

    test('a rescheduled game gets a new epoch with its new DateUtc', () {
      final before = applier.buildGameUpdates([
        feedGame(dateUtc: '2026-03-01 02:15:00Z'),
      ], const []);
      final after = applier.buildGameUpdates([
        feedGame(dateUtc: '2026-03-02 05:00:00Z'),
      ], const []);

      expect(
        after.single.attributes['DateUtcEpochMs'],
        isNot(before.single.attributes['DateUtcEpochMs']),
      );
      expect(after.single.attributes['DateUtcEpochMs'], 1772427600000);
    });

    test('leaves every other attribute as it was', () {
      final attributes = applier
          .buildGameUpdates([feedGame()], const [])
          .single
          .attributes;

      expect(attributes['HomeTeam'], 'Knights');
      expect(attributes['Location'], 'Allegiant Stadium');
      expect(attributes['RoundNumber'], 1);
      expect(attributes.keys, contains('HomeTeamScore'));
    });

    test('writes no epoch for a feed entry that has no DateUtc', () {
      final updates = applier.buildGameUpdates([
        feedGame(dateUtc: null),
      ], const []);

      expect(updates.single.attributes.containsKey('DateUtc'), isFalse);
      expect(updates.single.attributes.containsKey('DateUtcEpochMs'), isFalse);
    });

    test(
      'refuses a malformed DateUtc rather than write a game without a kickoff',
      () {
        expect(
          () => applier.buildGameUpdates([feedGame(dateUtc: 'TBC')], const []),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('nrl-01-001'),
            ),
          ),
        );
      },
    );

    test('refuses a DateUtc that is not a string', () {
      expect(
        () => applier.buildGameUpdates([feedGame(dateUtc: 12345)], const []),
        throwsFormatException,
      );
    });
  });
}
