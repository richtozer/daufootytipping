import 'package:test/test.dart';

import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/combined_rounds_service.dart';

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
      // Should be extended then buffered by 3 hours
      expect(
        r1.firstGameKickOffUTC,
        DateTime.parse('2023-01-01T08:00:00Z').toUtc().subtract(const Duration(hours: 3)),
      );
      expect(
        r1.lastGameKickOffUTC,
        DateTime.parse('2023-01-01T11:00:00Z').toUtc().add(const Duration(hours: 3)),
      );
    });

    test('fixOverlappingLeagueGameGroups adjusts overlapping league end times', () {
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
        DateTime.parse('2023-01-01T10:30:00Z').subtract(const Duration(days: 1, minutes: 1)),
      );
    });

    test('buildCombinedRounds end-to-end', () {
      final raw = [
        {'league': 'nrl', 'RoundNumber': 1, 'DateUtc': '2023-01-01T08:00:00Z', 'MatchNumber': 1},
        {'league': 'afl', 'RoundNumber': 1, 'DateUtc': '2023-01-01T09:00:00Z', 'MatchNumber': 1},
        {'league': 'nrl', 'RoundNumber': 2, 'DateUtc': '2023-02-02T08:00:00Z', 'MatchNumber': 1},
      ];
      final rounds = svc.buildCombinedRounds(raw);
      expect(rounds, isA<List<DAURound>>());
      // Based on current behavior, these three time-separated groups form 3 rounds
      expect(rounds.length, 3);
      expect(rounds.first.dAUroundNumber, 1);
      expect(rounds.last.dAUroundNumber, 3);
    });
  });
}
