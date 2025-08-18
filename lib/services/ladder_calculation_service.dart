import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/ladder_team.dart';
import 'package:daufootytipping/models/league_ladder.dart';

class LadderCalculationService {
  // Method to calculate the league ladder
  // It takes a list of all games, a list of all teams in the league, and the specific league
  LeagueLadder? calculateLadder({
    required List<Game> allGames,
    required List<Team> leagueTeams,
    required League league,
    DateTime? cutoffDate,
  }) {
    // 1. Filter games by cutoff date
    if (cutoffDate != null) {
      allGames = allGames
          .where((game) => game.startTimeUTC.isBefore(cutoffDate))
          .toList();
    }

    // 2. Filter out dummy teams
    final activeTeams =
        leagueTeams.where((team) => team.name != 'To be announced').toList();

    // 3. Group games by round
    Map<int, List<Game>> gamesByRound = {};
    for (var game in allGames.where((g) => g.league == league)) {
      gamesByRound.putIfAbsent(game.fixtureRoundNumber, () => []).add(game);
    }

    // 4. Identify completed rounds
    final now = DateTime.now().toUtc();
    final completedRoundNumbers = gamesByRound.entries
        .where((entry) {
          if (entry.value.isEmpty) return false;
          final allGamesHaveScores = entry.value.every((g) =>
              g.scoring != null &&
              g.scoring!.homeTeamScore != null &&
              g.scoring!.awayTeamScore != null);
          if (!allGamesHaveScores) return false;
          DateTime lastGameStartTime = entry.value.first.startTimeUTC;
          for (var game in entry.value) {
            if (game.startTimeUTC.isAfter(lastGameStartTime)) {
              lastGameStartTime = game.startTimeUTC;
            }
          }
          return now.isAfter(lastGameStartTime.add(const Duration(hours: 3)));
        })
        .map((entry) => entry.key)
        .toList();

    // 5. Check for min completed rounds
    if (completedRoundNumbers.length < 3) {
      return null;
    }

    // 6. Initialize ladder teams
    Map<String, LadderTeam> ladderTeamsMap = {};
    for (var team in activeTeams) {
      if (team.league == league) {
        ladderTeamsMap[team.dbkey] = LadderTeam(
          dbkey: team.dbkey,
          teamName: team.name,
          logoURI: team.logoURI,
        );
      }
    }

    // 7. Handle Byes
    if (league == League.nrl) {
      final allTeamKeysInLeague = activeTeams.map((t) => t.dbkey).toSet();
      for (var roundNumber in completedRoundNumbers) {
        final gamesInRound = gamesByRound[roundNumber] ?? [];
        final teamsThatPlayed = <String>{};
        for (var game in gamesInRound) {
          teamsThatPlayed.add(game.homeTeam.dbkey);
          teamsThatPlayed.add(game.awayTeam.dbkey);
        }
        final teamsWithBye = allTeamKeysInLeague.difference(teamsThatPlayed);
        for (var teamKey in teamsWithBye) {
          final ladderTeam = ladderTeamsMap[teamKey];
          if (ladderTeam != null) {
            ladderTeam.points += 2;
            ladderTeam.byes += 1;
            ladderTeam.played++;
          }
        }
      }
    }

    // 8. Process games
    List<Game> relevantGames = allGames.where((game) {
      return game.league == league &&
          game.scoring != null &&
          game.scoring!.homeTeamScore != null &&
          game.scoring!.awayTeamScore != null;
    }).toList();

    for (var game in relevantGames) {
      LadderTeam? homeLadderTeam = ladderTeamsMap[game.homeTeam.dbkey];
      LadderTeam? awayLadderTeam = ladderTeamsMap[game.awayTeam.dbkey];

      if (homeLadderTeam == null || awayLadderTeam == null) {
        continue;
      }

      homeLadderTeam.played++;
      awayLadderTeam.played++;

      homeLadderTeam.pointsFor += game.scoring!.homeTeamScore!;
      homeLadderTeam.pointsAgainst += game.scoring!.awayTeamScore!;
      awayLadderTeam.pointsFor += game.scoring!.awayTeamScore!;
      awayLadderTeam.pointsAgainst += game.scoring!.homeTeamScore!;

      if (game.scoring!.homeTeamScore! > game.scoring!.awayTeamScore!) {
        homeLadderTeam.won++;
        awayLadderTeam.lost++;
        if (league == League.afl) {
          homeLadderTeam.points += 4;
        } else {
          homeLadderTeam.points += 2;
        }
      } else if (game.scoring!.awayTeamScore! > game.scoring!.homeTeamScore!) {
        awayLadderTeam.won++;
        homeLadderTeam.lost++;
        if (league == League.afl) {
          awayLadderTeam.points += 4;
        } else {
          awayLadderTeam.points += 2;
        }
      } else {
        homeLadderTeam.drawn++;
        awayLadderTeam.drawn++;
        if (league == League.afl) {
          homeLadderTeam.points += 2;
          awayLadderTeam.points += 2;
        } else {
          homeLadderTeam.points += 1;
          awayLadderTeam.points += 1;
        }
      }
    }

    // 9. Calculate percentage and sort
    for (var ladderTeam in ladderTeamsMap.values) {
      ladderTeam.calculatePercentage();
    }

    List<LadderTeam> finalLadderTeams = ladderTeamsMap.values.toList();
    LeagueLadder leagueLadder = LeagueLadder(
      league: league,
      teams: finalLadderTeams,
    );
    leagueLadder.sortLadder();

    leagueLadder.teams.removeWhere(
      (team) => team.points == 0 && team.played == 0,
    );

    return leagueLadder;
  }
}
