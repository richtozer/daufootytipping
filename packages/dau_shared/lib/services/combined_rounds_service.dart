import 'package:collection/collection.dart';
import '../models/dauround.dart';

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
          return {'league-round': e.key, 'games': e.value, ...times};
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
          lastEndDate = groupEndDate.subtract(
            const Duration(days: 1, minutes: 1),
          );
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
      final DateTime groupMinStartTime = (group['minStartTime'] as DateTime)
          .toUtc();
      final DateTime groupMaxStartTime = (group['maxStartTime'] as DateTime)
          .toUtc();

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
        // Rounds start at 0:00 UTC on a date, so a group that starts on or
        // before the UTC date of the current round's last game joins it.
        // Otherwise two rounds could start on the same date.
        if (!_utcDate(
          groupMinStartTime,
        ).isAfter(_utcDate(lastCombinedRound.lastGameKickOffUTC))) {
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

    // Set each round's start to 0:00 UTC on the first game's UTC date,
    // and pad the round's end by 3 hours after the last game kickoff.
    for (final round in combinedRounds) {
      round.firstGameKickOffUTC = _utcDate(round.firstGameKickOffUTC);
      round.lastGameKickOffUTC = round.lastGameKickOffUTC.add(
        const Duration(hours: 3),
      );
    }
    return combinedRounds;
  }

  static DateTime _utcDate(DateTime time) {
    final utc = time.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  List<DAURound> buildCombinedRounds(List<dynamic> rawGames) {
    final groups = groupGamesByLeagueAndRound(
      rawGames.cast<Map<dynamic, dynamic>>(),
    );
    final sorted = sortGameGroupsByStartTimeThenMatchNumber(
      groups,
    ).cast<Map<String, dynamic>>();
    final fixed = fixOverlappingLeagueGameGroups(sorted);
    return combineGameGroupsIntoRounds(fixed);
  }
}
