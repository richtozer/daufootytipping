import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:dau_shared/services/combined_rounds_service.dart';

void main() {
  group('CombinedRoundsService', () {
    final svc = CombinedRoundsService();

    test('groupGamesByLeagueAndRound groups by league and round', () {
      final games = [
        {'league': 'nrl', 'RoundNumber': 1, 'DateUtc': '2023-01-01T10:00:00Z'},
        {'league': 'nrl', 'RoundNumber': 1, 'DateUtc': '2023-01-01T12:00:00Z'},
        {'league': 'afl', 'RoundNumber': 1, 'DateUtc': '2023-01-02T10:00:00Z'},
        {'league': 'nrl', 'RoundNumber': 2, 'DateUtc': '2023-01-03T10:00:00Z'},
      ];
      final grouped = svc.groupGamesByLeagueAndRound(games);
      expect(grouped.length, 3);
      expect(grouped['nrl-1']!.length, 2);
      expect(grouped['afl-1']!.length, 1);
      expect(grouped['nrl-2']!.length, 1);
    });

    test('sortGameGroupsByStartTimeThenMatchNumber sorts as expected', () {
      final groups = {
        'nrl-1': [
          {'DateUtc': '2023-01-01T10:00:00Z', 'MatchNumber': 2},
          {'DateUtc': '2023-01-01T12:00:00Z', 'MatchNumber': 3},
        ],
        'afl-1': [
          {'DateUtc': '2023-01-02T10:00:00Z', 'MatchNumber': 1},
        ],
        'nrl-2': [
          {'DateUtc': '2023-01-01T08:00:00Z', 'MatchNumber': 1},
        ],
      };
      final sorted = svc.sortGameGroupsByStartTimeThenMatchNumber(groups);
      expect(sorted.length, 3);
      expect(sorted[0]!['league-round'], 'nrl-2');
      expect(sorted[1]!['league-round'], 'nrl-1');
      expect(sorted[2]!['league-round'], 'afl-1');
    });

    test('sortGameGroupsByStartTimeThenMatchNumber tiebreaks by MatchNumber', () {
      final groups = {
        'nrl-1': [
          {'DateUtc': '2023-01-01T10:00:00Z', 'MatchNumber': 5},
        ],
        'nrl-2': [
          {'DateUtc': '2023-01-01T10:00:00Z', 'MatchNumber': 1},
        ],
      };
      final sorted = svc.sortGameGroupsByStartTimeThenMatchNumber(groups);
      expect(sorted.length, 2);
      // Same minStartTime, 'nrl-2' first because its first MatchNumber is lower
      expect(sorted[0]!['league-round'], 'nrl-2');
      expect(sorted[1]!['league-round'], 'nrl-1');
    });

    test('combineGameGroupsIntoRounds merges overlapping groups and buffers times', () {
      final sortedGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ],
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-01T09:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T11:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T09:00:00Z'},
            {'DateUtc': '2023-01-01T11:00:00Z'},
          ],
        },
      ];

      final rounds = svc.combineGameGroupsIntoRounds(
        sortedGroups.cast<Map<String, dynamic>>(),
      );

      expect(rounds.length, 1);
      final r1 = rounds.first;
      // Start is 0:00 UTC on the first game's UTC date; end retains +3h buffer
      expect(r1.firstGameKickOffUTC, DateTime.utc(2023, 1, 1));
      expect(
        r1.lastGameKickOffUTC,
        DateTime.parse('2023-01-01T11:00:00Z')
            .toUtc()
            .add(const Duration(hours: 3)),
      );
    });

    test('combineGameGroupsIntoRounds joins league groups on the same UTC date into one round, and starts strictly increase', () {
      final sortedGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.utc(2026, 3, 4, 9, 0),
          'maxStartTime': DateTime.utc(2026, 3, 5, 2, 0),
          'games': <Map<String, dynamic>>[],
        },
        // Starts later on the same UTC date as nrl-1's last game.
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.utc(2026, 3, 5, 9, 0),
          'maxStartTime': DateTime.utc(2026, 3, 7, 6, 0),
          'games': <Map<String, dynamic>>[],
        },
        {
          'league-round': 'nrl-2',
          'minStartTime': DateTime.utc(2026, 3, 12, 9, 0),
          'maxStartTime': DateTime.utc(2026, 3, 14, 6, 0),
          'games': <Map<String, dynamic>>[],
        },
      ];

      final rounds = svc.combineGameGroupsIntoRounds(
        sortedGroups.cast<Map<String, dynamic>>(),
      );

      expect(rounds, hasLength(2));
      expect(rounds[0].getRoundStartDate(), DateTime.utc(2026, 3, 4));
      expect(rounds[0].lastGameKickOffUTC, DateTime.utc(2026, 3, 7, 9, 0));
      expect(rounds[1].getRoundStartDate(), DateTime.utc(2026, 3, 12));
      for (var i = 1; i < rounds.length; i++) {
        expect(
          rounds[i].getRoundStartDate().isAfter(
            rounds[i - 1].getRoundStartDate(),
          ),
          isTrue,
        );
      }
    });

    test('combineGameGroupsIntoRounds sets start to 0:00 UTC on same date even for 01:30 UTC kickoff', () {
      final sortedGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.utc(2026, 3, 5, 1, 30),
          'maxStartTime': DateTime.utc(2026, 3, 5, 3, 30),
          'games': [
            {'DateUtc': '2026-03-05T01:30:00Z'},
            {'DateUtc': '2026-03-05T03:30:00Z'},
          ],
        },
      ];

      final rounds = svc.combineGameGroupsIntoRounds(
        sortedGroups.cast<Map<String, dynamic>>(),
      );

      expect(rounds, hasLength(1));
      expect(rounds.first.firstGameKickOffUTC, DateTime.utc(2026, 3, 5));
      expect(rounds.first.lastGameKickOffUTC, DateTime.utc(2026, 3, 5, 6, 30));
    });

    test(
      'fixOverlappingLeagueGameGroups adjusts overlapping league end times',
      () {
        final sorted = [
          {
            'league-round': 'nrl-1',
            'minStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
            'maxStartTime': DateTime.parse('2023-01-01T11:00:00Z'),
            'games': [],
          },
          {
            'league-round': 'nrl-2',
            'minStartTime': DateTime.parse('2023-01-01T10:30:00Z'),
            'maxStartTime': DateTime.parse('2023-01-01T12:00:00Z'),
            'games': [],
          },
        ];
        final fixed = svc.fixOverlappingLeagueGameGroups(
          sorted.cast<Map<String, dynamic>>(),
        );
        expect(fixed.length, 2);
        // Mirrors existing behavior: subtract 1 day + 1 minute
        expect(
          fixed.first['maxStartTime'],
          DateTime.parse('2023-01-01T10:30:00Z')
              .subtract(const Duration(days: 1, minutes: 1)),
        );
      },
    );

    test('buildCombinedRounds end-to-end', () {
      final raw = [
        {
          'league': 'nrl',
          'RoundNumber': 1,
          'DateUtc': '2023-01-01T08:00:00Z',
          'MatchNumber': 1,
        },
        {
          'league': 'afl',
          'RoundNumber': 1,
          'DateUtc': '2023-01-01T09:00:00Z',
          'MatchNumber': 1,
        },
        {
          'league': 'nrl',
          'RoundNumber': 2,
          'DateUtc': '2023-02-02T08:00:00Z',
          'MatchNumber': 1,
        },
      ];
      final rounds = svc.buildCombinedRounds(raw);
      expect(rounds, isA<List<DAURound>>());
      // nrl-1 and afl-1 share a UTC date, so they form one round; nrl-2 is
      // a month later and forms the second.
      expect(rounds.length, 2);
      expect(rounds.first.dAUroundNumber, 1);
      expect(rounds.first.getRoundStartDate(), DateTime.utc(2023, 1, 1));
      expect(rounds.last.dAUroundNumber, 2);
      expect(rounds.last.getRoundStartDate(), DateTime.utc(2023, 2, 2));
    });
  });
}
