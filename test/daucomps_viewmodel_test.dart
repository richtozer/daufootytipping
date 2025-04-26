import 'package:collection/collection.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:test/test.dart';

Map<String, List<Map<dynamic, dynamic>>> _groupGamesByLeagueAndRound(
    List<Map<dynamic, dynamic>> games) {
  return groupBy(
      games,
      (Map<dynamic, dynamic> rawGame) =>
          '${rawGame["league"]}-${rawGame["RoundNumber"]}');
}

Map<String, DateTime> _calculateStartEndTimes(
    List<Map<dynamic, dynamic>> rawGames) {
  var minStartTime = rawGames
      .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
      .reduce((a, b) => a.isBefore(b) ? a : b);
  var maxStartTime = rawGames
      .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return {'minStartTime': minStartTime, 'maxStartTime': maxStartTime};
}

List<Map<String, Object>?> _sortGameGroupsByStartTimeThenMatchNumber(
    Map<String, List<Map<dynamic, dynamic>>> groups) {
  return groups.entries
      .map((e) {
        if (e.value.isEmpty) return null;
        var times = _calculateStartEndTimes(e.value);
        return {
          'league-round': e.key, // Add the key from the passed-in groups
          'games': e.value,
          ...times
        };
      })
      .where((group) => group != null)
      .toList()
    ..sort((a, b) {
      int startTimeCompare = (a!['minStartTime'] as DateTime)
          .compareTo(b!['minStartTime'] as DateTime);
      if (startTimeCompare == 0) {
        return (a['games'] as List<Map>)
            .first['MatchNumber']
            .compareTo((b['games'] as List<Map>).first['MatchNumber']);
      }
      return startTimeCompare;
    });
}

List<DAURound> _combineGameGroupsIntoRounds(
    List<Map<String, dynamic>> sortedGameGroups) {
  List<DAURound> combinedRounds = [];
  for (var group in sortedGameGroups) {
    DateTime groupMinStartTime = (group['minStartTime'] as DateTime).toUtc();
    DateTime groupMaxStartTime = (group['maxStartTime'] as DateTime).toUtc();

    if (combinedRounds.isEmpty) {
      combinedRounds.add(DAURound(
          dAUroundNumber: combinedRounds.length + 1,
          firstGameKickOffUTC: groupMinStartTime,
          lastGameKickOffUTC: groupMaxStartTime,
          games: []));
    } else {
      DAURound lastCombinedRound = combinedRounds.last;
      if (groupMinStartTime.isBefore(lastCombinedRound.lastGameKickOffUTC) ||
          groupMinStartTime
              .isAtSameMomentAs(lastCombinedRound.lastGameKickOffUTC)) {
        // extend the combined round to include the overlapping league

        lastCombinedRound.lastGameKickOffUTC =
            groupMaxStartTime.isAfter(lastCombinedRound.lastGameKickOffUTC)
                ? groupMaxStartTime
                : lastCombinedRound.lastGameKickOffUTC;
      } else {
        // start a new round
        combinedRounds.add(DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            firstGameKickOffUTC: groupMinStartTime,
            lastGameKickOffUTC: groupMaxStartTime,
            games: []));
      }
    }
  }

  return combinedRounds;
}

List<Map<String, dynamic>> _fixOverlappingLeagueGameGroups(
    List<Map<String, dynamic>> sortedGameGroups) {
  // filter on each league i.e 'nrl-*' then 'afl-*'
  // loop through the groups for that league, if any overlap,
  // modify the end date of the last group, to be just before the start date of the next group
  List<Map<String, dynamic>> fixedGameGroups = [];
  var groupedByLeague = groupBy(sortedGameGroups, (Map<String, dynamic> group) {
    return group['league-round'].toString().split('-')[0];
  });
  groupedByLeague.forEach((league, groups) {
    DateTime lastEndDate = DateTime.fromMillisecondsSinceEpoch(0);
    for (var group in groups) {
      DateTime groupStartDate = group['minStartTime'];
      DateTime groupEndDate = group['maxStartTime'];

      if (groupStartDate.isBefore(lastEndDate)) {
        // Adjust the end date of the last fixedGameGroup
        lastEndDate = groupEndDate;
        fixedGameGroups.last['maxStartTime'] =
            groupStartDate.subtract(Duration(minutes: 1));
      } else {
        lastEndDate = groupEndDate;
      }
      fixedGameGroups.add(group);
    }
  });
  return fixedGameGroups;
}

void main() {
  group('DAUCompsViewModel', () {
    test('groupGamesByLeagueAndRound groups games correctly', () {
      final games = [
        {'league': 'nrl', 'RoundNumber': 1, 'DateUtc': '2023-01-01T10:00:00Z'},
        {'league': 'nrl', 'RoundNumber': 1, 'DateUtc': '2023-08-01T12:00:00Z'},
        {'league': 'afl', 'RoundNumber': 1, 'DateUtc': '2023-01-02T10:00:00Z'},
        {'league': 'nrl', 'RoundNumber': 2, 'DateUtc': '2023-01-03T10:00:00Z'},
      ];

      final groupedGames = _groupGamesByLeagueAndRound(games);

      expect(groupedGames.length, 3);
      expect(groupedGames['nrl-1']!.length, 2);
      expect(groupedGames['afl-1']!.length, 1);
      expect(groupedGames['nrl-2']!.length, 1);
    });

    test('calculateStartEndTimes calculates correct times', () {
      final games = [
        {'DateUtc': '2023-01-01T10:00:00Z'},
        {'DateUtc': '2023-01-01T12:00:00Z'},
        {'DateUtc': '2023-01-01T08:00:00Z'},
      ];

      final times = _calculateStartEndTimes(games);

      expect(times['minStartTime'], DateTime.parse('2023-01-01T08:00:00Z'));
      expect(times['maxStartTime'], DateTime.parse('2023-01-01T12:00:00Z'));
    });

    test('sortGameGroupsByStartTimeThenMatchNumber sorts correctly', () {
      final groups = {
        'nrl-1': [
          {'DateUtc': '2023-01-01T10:00:00Z'},
          {'DateUtc': '2023-01-01T12:00:00Z'},
        ],
        'afl-1': [
          {'DateUtc': '2023-01-02T10:00:00Z'},
        ],
        'nrl-2': [
          {'DateUtc': '2023-01-01T08:00:00Z'},
        ],
      };

      final sortedGroups = _sortGameGroupsByStartTimeThenMatchNumber(groups);

      expect(sortedGroups.length, 3);
      expect(sortedGroups[0]!['league-round'], 'nrl-2');
      expect(sortedGroups[1]!['league-round'], 'nrl-1');
      expect(sortedGroups[2]!['league-round'], 'afl-1');
    });

    test('combineGameGroupsIntoRounds combines groups into rounds correctly',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T09:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ]
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T12:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T10:00:00Z'},
            {'DateUtc': '2023-01-01T12:00:00Z'},
          ]
        },
        {
          'league-round': 'nrl-2',
          'minStartTime': DateTime.parse('2023-02-02T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-02-02T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-02-02T08:00:00Z'},
            {'DateUtc': '2023-02-02T10:00:00Z'},
          ]
        },
      ];

      final combinedRounds = _combineGameGroupsIntoRounds(sortedGameGroups);

      expect(combinedRounds.length, 2, reason: 'Should combine into 2 rounds');

      // First round
      expect(combinedRounds[0].dAUroundNumber, 1, reason: 'First round');
      expect(combinedRounds[0].firstGameKickOffUTC,
          DateTime.parse('2023-01-01T08:00:00Z'),
          reason: 'Start date');
      expect(combinedRounds[0].lastGameKickOffUTC,
          DateTime.parse('2023-01-01T12:00:00Z'),
          reason: 'End date');

      // Second round
      expect(combinedRounds[1].dAUroundNumber, 2, reason: 'Second round');
      expect(combinedRounds[1].firstGameKickOffUTC,
          DateTime.parse('2023-02-02T08:00:00Z'),
          reason: 'Start date');
      expect(combinedRounds[1].lastGameKickOffUTC,
          DateTime.parse('2023-02-02T10:00:00Z'),
          reason: 'End date');
    });

    test(
        'combineGameGroupsIntoRounds handles overlapping rounds correctly by extending the end date',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ]
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-01T09:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T11:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T09:00:00Z'},
            {'DateUtc': '2023-01-01T11:00:00Z'},
          ]
        },
      ];

      final combinedRounds = _combineGameGroupsIntoRounds(sortedGameGroups);

      expect(combinedRounds.length, 1);

      // Single combined round
      expect(combinedRounds[0].dAUroundNumber, 1);
      expect(combinedRounds[0].firstGameKickOffUTC,
          DateTime.parse('2023-01-01T08:00:00Z'));
      expect(combinedRounds[0].lastGameKickOffUTC,
          DateTime.parse('2023-01-01T11:00:00Z'));
    });

    test(
        'combineGameGroupsIntoRounds starts a new round when there is no overlap',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ]
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-02T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-02T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-02T08:00:00Z'},
            {'DateUtc': '2023-01-02T10:00:00Z'},
          ]
        },
      ];

      final combinedRounds = _combineGameGroupsIntoRounds(sortedGameGroups);

      expect(combinedRounds.length, 2);

      // First round
      expect(combinedRounds[0].dAUroundNumber, 1);
      expect(combinedRounds[0].firstGameKickOffUTC,
          DateTime.parse('2023-01-01T08:00:00Z'));
      expect(combinedRounds[0].lastGameKickOffUTC,
          DateTime.parse('2023-01-01T10:00:00Z'));

      // Second round
      expect(combinedRounds[1].dAUroundNumber, 2);
      expect(combinedRounds[1].firstGameKickOffUTC,
          DateTime.parse('2023-01-02T08:00:00Z'));
      expect(combinedRounds[1].lastGameKickOffUTC,
          DateTime.parse('2023-01-02T10:00:00Z'));
    });

    test(
        '_fixOverlappingLeagueGameGroups adjusts overlapping groups correctly within the same league',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-02-02T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-02-02T10:00:00Z'},
          ]
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-01T09:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T11:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T09:00:00Z'},
            {'DateUtc': '2023-01-01T11:00:00Z'},
          ]
        },
        {
          'league-round': 'nrl-2',
          'minStartTime': DateTime.parse('2023-01-02T09:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-02T11:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-02T09:00:00Z'},
            {'DateUtc': '2023-01-02T11:00:00Z'},
          ]
        },
      ];

      final fixedGameGroups = _fixOverlappingLeagueGameGroups(sortedGameGroups);

      expect(fixedGameGroups.length, 3);

      // Check that the overlapping groups in 'nrl' are adjusted
      expect(fixedGameGroups[0]['league-round'], 'nrl-1');
      expect(
          fixedGameGroups[0]['maxStartTime'],
          DateTime.parse('2023-01-02T09:00:00Z')
              .subtract(Duration(minutes: 1)));

      expect(fixedGameGroups[1]['league-round'], 'nrl-2');
      expect(fixedGameGroups[1]['minStartTime'],
          DateTime.parse('2023-01-02T09:00:00Z'));

      // Check that 'afl' group remains unchanged
      expect(fixedGameGroups[2]['league-round'], 'afl-1');
      expect(fixedGameGroups[2]['minStartTime'],
          DateTime.parse('2023-01-01T09:00:00Z'));
      expect(fixedGameGroups[2]['maxStartTime'],
          DateTime.parse('2023-01-01T11:00:00Z'));
    });

    test(
        '_fixOverlappingLeagueGameGroups handles non-overlapping groups correctly',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ]
        },
        {
          'league-round': 'nrl-2',
          'minStartTime': DateTime.parse('2023-01-02T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-02T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-02T08:00:00Z'},
            {'DateUtc': '2023-01-02T10:00:00Z'},
          ]
        },
        {
          'league-round': 'afl-1',
          'minStartTime': DateTime.parse('2023-01-03T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-03T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-03T08:00:00Z'},
            {'DateUtc': '2023-01-03T10:00:00Z'},
          ]
        },
      ];

      final fixedGameGroups = _fixOverlappingLeagueGameGroups(sortedGameGroups);

      expect(fixedGameGroups.length, 3);

      // Check that all groups remain unchanged
      expect(fixedGameGroups[0]['league-round'], 'nrl-1');
      expect(fixedGameGroups[0]['minStartTime'],
          DateTime.parse('2023-01-01T08:00:00Z'));
      expect(fixedGameGroups[0]['maxStartTime'],
          DateTime.parse('2023-01-01T10:00:00Z'));

      expect(fixedGameGroups[1]['league-round'], 'nrl-2');
      expect(fixedGameGroups[1]['minStartTime'],
          DateTime.parse('2023-01-02T08:00:00Z'));
      expect(fixedGameGroups[1]['maxStartTime'],
          DateTime.parse('2023-01-02T10:00:00Z'));

      expect(fixedGameGroups[2]['league-round'], 'afl-1');
      expect(fixedGameGroups[2]['minStartTime'],
          DateTime.parse('2023-01-03T08:00:00Z'));
      expect(fixedGameGroups[2]['maxStartTime'],
          DateTime.parse('2023-01-03T10:00:00Z'));
    });

    test(
        '_fixOverlappingLeagueGameGroups handles multiple overlapping groups within the same league',
        () {
      final sortedGameGroups = [
        {
          'league-round': 'nrl-1',
          'minStartTime': DateTime.parse('2023-01-01T08:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T10:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T08:00:00Z'},
            {'DateUtc': '2023-01-01T10:00:00Z'},
          ]
        },
        {
          'league-round': 'nrl-2',
          'minStartTime': DateTime.parse('2023-01-01T09:00:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T11:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T09:00:00Z'},
            {'DateUtc': '2023-01-01T11:00:00Z'},
          ]
        },
        {
          'league-round': 'nrl-3',
          'minStartTime': DateTime.parse('2023-01-01T10:30:00Z'),
          'maxStartTime': DateTime.parse('2023-01-01T12:00:00Z'),
          'games': [
            {'DateUtc': '2023-01-01T10:30:00Z'},
            {'DateUtc': '2023-01-01T12:00:00Z'},
          ]
        },
      ];

      final fixedGameGroups = _fixOverlappingLeagueGameGroups(sortedGameGroups);

      expect(fixedGameGroups.length, 3);

      // Check that the overlapping groups are adjusted
      expect(fixedGameGroups[0]['league-round'], 'nrl-1');
      expect(
          fixedGameGroups[0]['maxStartTime'],
          DateTime.parse('2023-01-01T09:00:00Z')
              .subtract(Duration(minutes: 1)));

      expect(fixedGameGroups[1]['league-round'], 'nrl-2');
      expect(
          fixedGameGroups[1]['maxStartTime'],
          DateTime.parse('2023-01-01T10:30:00Z')
              .subtract(Duration(minutes: 1)));

      expect(fixedGameGroups[2]['league-round'], 'nrl-3');
      expect(fixedGameGroups[2]['minStartTime'],
          DateTime.parse('2023-01-01T10:30:00Z'));
      expect(fixedGameGroups[2]['maxStartTime'],
          DateTime.parse('2023-01-01T12:00:00Z'));
    });
  });
}
