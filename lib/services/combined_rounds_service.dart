import 'package:collection/collection.dart';
import 'package:daufootytipping/models/dauround.dart';

class CombinedRoundsService {
  Map<String, List<Map<dynamic, dynamic>>> groupGamesByLeagueAndRound(
    List<Map<dynamic, dynamic>> games,
  ) {
    return groupBy(
      games,
      (Map<dynamic, dynamic> rawGame) =>
          '${rawGame["league"]}-${rawGame["RoundNumber"]}',
    );
  }

  Map<String, DateTime> calculateStartEndTimes(
    List<Map<dynamic, dynamic>> rawGames,
  ) {
    final minStartTime = rawGames
        .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final maxStartTime = rawGames
        .map((rawGame) => DateTime.parse(rawGame["DateUtc"]))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return {'minStartTime': minStartTime, 'maxStartTime': maxStartTime};
  }

  List<Map<String, Object>?> sortGameGroupsByStartTimeThenMatchNumber(
    Map<String, List<Map<dynamic, dynamic>>> groups,
  ) {
    return groups.entries
        .map((e) {
          if (e.value.isEmpty) return null;
          final times = calculateStartEndTimes(e.value);
          return {
            'league-round': e.key,
            'games': e.value,
            ...times,
          };
        })
        .where((group) => group != null)
        .toList()
      ..sort((a, b) {
        final startTimeCompare = (a!['minStartTime'] as DateTime).compareTo(
          b!['minStartTime'] as DateTime,
        );
        if (startTimeCompare == 0) {
          return (a['games'] as List<Map>).first['MatchNumber'].compareTo(
            (b['games'] as List<Map>).first['MatchNumber'],
          );
        }
        return startTimeCompare;
      });
  }

  List<Map<String, dynamic>> fixOverlappingLeagueGameGroups(
    List<Map<String, dynamic>> sortedGameGroups,
  ) {
    final fixedGameGroups = <Map<String, dynamic>>[];
    final groupedByLeague = groupBy(sortedGameGroups, (
      Map<String, dynamic> group,
    ) {
      return group['league-round'].toString().split('-')[0];
    });
    groupedByLeague.forEach((league, groups) {
      DateTime lastEndDate = DateTime.fromMillisecondsSinceEpoch(0);
      for (final group in groups) {
        final DateTime groupStartDate = group['minStartTime'];
        final DateTime groupEndDate = group['maxStartTime'];

        if (groupStartDate.isBefore(lastEndDate)) {
          // Note: behavior mirrors current implementation (subtract 1 day + 1 minute)
          lastEndDate = groupEndDate.subtract(const Duration(days: 1, minutes: 1));
          fixedGameGroups.last['maxStartTime'] = groupStartDate.subtract(
            const Duration(days: 1, minutes: 1),
          );
        } else {
          lastEndDate = groupEndDate;
        }
        fixedGameGroups.add(group);
      }
    });
    fixedGameGroups.sort((a, b) {
      return (a['minStartTime'] as DateTime).compareTo(
        b['minStartTime'] as DateTime,
      );
    });
    return fixedGameGroups;
  }

  List<DAURound> combineGameGroupsIntoRounds(
    List<Map<String, dynamic>> sortedGameGroups,
  ) {
    final combinedRounds = <DAURound>[];
    for (final group in sortedGameGroups) {
      final DateTime groupMinStartTime =
          (group['minStartTime'] as DateTime).toUtc();
      final DateTime groupMaxStartTime =
          (group['maxStartTime'] as DateTime).toUtc();

      if (combinedRounds.isEmpty) {
        combinedRounds.add(
          DAURound(
            dAUroundNumber: combinedRounds.length + 1,
            firstGameKickOffUTC: groupMinStartTime,
            lastGameKickOffUTC: groupMaxStartTime,
            games: const [],
          ),
        );
      } else {
        final DAURound lastCombinedRound = combinedRounds.last;
        if (groupMinStartTime.isBefore(lastCombinedRound.lastGameKickOffUTC) ||
            groupMinStartTime.isAtSameMomentAs(
              lastCombinedRound.lastGameKickOffUTC,
            )) {
          lastCombinedRound.lastGameKickOffUTC =
              groupMaxStartTime.isAfter(lastCombinedRound.lastGameKickOffUTC)
              ? groupMaxStartTime
              : lastCombinedRound.lastGameKickOffUTC;
        } else {
          combinedRounds.add(
            DAURound(
              dAUroundNumber: combinedRounds.length + 1,
              firstGameKickOffUTC: groupMinStartTime,
              lastGameKickOffUTC: groupMaxStartTime,
              games: const [],
            ),
          );
        }
      }
    }

    // Add buffer of 3 hours to start and end times (retain existing behavior)
    for (final round in combinedRounds) {
      round.firstGameKickOffUTC = round.firstGameKickOffUTC.subtract(
        const Duration(hours: 3),
      );
      round.lastGameKickOffUTC = round.lastGameKickOffUTC.add(
        const Duration(hours: 3),
      );
    }
    return combinedRounds;
  }

  List<DAURound> buildCombinedRounds(List<dynamic> rawGames) {
    final groups = groupGamesByLeagueAndRound(
      rawGames.cast<Map<dynamic, dynamic>>(),
    );
    final sorted = sortGameGroupsByStartTimeThenMatchNumber(groups)
        .cast<Map<String, dynamic>>();
    final fixed = fixOverlappingLeagueGameGroups(sorted);
    return combineGameGroupsIntoRounds(fixed);
  }
}

