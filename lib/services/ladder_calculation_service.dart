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
  }) {
    // --- Count completed rounds ---
    // Group games by round number
    Map<int, List<Game>> gamesByRound = {};
    for (var game in allGames.where((g) => g.league == league)) {
      gamesByRound.putIfAbsent(game.fixtureRoundNumber, () => []).add(game);
    }
    // Count rounds where all games have scores
    int completedRounds = gamesByRound.values
        .where((games) => games.every((g) =>
            g.scoring != null &&
            g.scoring!.homeTeamScore != null &&
            g.scoring!.awayTeamScore != null))
        .length;

    // Wait until at least 3 rounds are completed before showing ladder
    if (completedRounds < 3) {
      return null;
    }
    // Initialize LadderTeam objects for each team in the league
    Map<String, LadderTeam> ladderTeamsMap = {};
    for (var team in leagueTeams) {
      // Ensure we only add teams that are part of the specified league
      // This check might be redundant if leagueTeams is already filtered,
      // but it's a good safeguard.
      if (team.league == league) {
        ladderTeamsMap[team.dbkey] = LadderTeam(
            dbkey: team.dbkey, teamName: team.name, logoURI: team.logoURI);
      }
    }

    // Filter games for the specified league and where scores are available
    List<Game> relevantGames = allGames.where((game) {
      return game.league == league &&
          game.scoring != null &&
          game.scoring!.homeTeamScore != null &&
          game.scoring!.awayTeamScore != null;
    }).toList();

    // Process each relevant game
    for (var game in relevantGames) {
      // Ensure homeTeam and awayTeam are not null before accessing dbkey
      LadderTeam? homeLadderTeam = ladderTeamsMap[game.homeTeam.dbkey];
      LadderTeam? awayLadderTeam = ladderTeamsMap[game.awayTeam.dbkey];

      if (homeLadderTeam == null || awayLadderTeam == null) {
        // This implies a team played in a game but wasn't in the initial leagueTeams list for that league.
        log('Warning: Team data not found in ladderTeamsMap for game ${game.dbkey}. Home: ${game.homeTeam.name}, Away: ${game.awayTeam.name}');
        continue;
      }

      // Update played count
      homeLadderTeam.played++;
      awayLadderTeam.played++;

      // Update points for and against (scores are checked for nullity in relevantGames filter)
      homeLadderTeam.pointsFor += game.scoring!.homeTeamScore!;
      homeLadderTeam.pointsAgainst += game.scoring!.awayTeamScore!;
      awayLadderTeam.pointsFor += game.scoring!.awayTeamScore!;
      awayLadderTeam.pointsAgainst += game.scoring!.homeTeamScore!;

      // Determine winner and update stats
      if (game.scoring!.homeTeamScore! > game.scoring!.awayTeamScore!) {
        // Home team wins
        homeLadderTeam.won++;
        awayLadderTeam.lost++;
        if (league == League.afl) {
          homeLadderTeam.points += 4;
        } else {
          // Assuming NRL or other leagues default to 2 points for a win
          homeLadderTeam.points += 2;
        }
      } else if (game.scoring!.awayTeamScore! > game.scoring!.homeTeamScore!) {
        // Away team wins
        awayLadderTeam.won++;
        homeLadderTeam.lost++;
        if (league == League.afl) {
          awayLadderTeam.points += 4;
        } else {
          // Assuming NRL or other leagues default to 2 points for a win
          awayLadderTeam.points += 2;
        }
      } else {
        // Draw
        homeLadderTeam.drawn++;
        awayLadderTeam.drawn++;
        if (league == League.afl) {
          homeLadderTeam.points += 2;
          awayLadderTeam.points += 2;
        } else {
          // Assuming NRL or other leagues default to 1 point for a draw
          homeLadderTeam.points += 1;
          awayLadderTeam.points += 1;
        }
      }
    }

    // Calculate percentage for each team
    for (var ladderTeam in ladderTeamsMap.values) {
      ladderTeam.calculatePercentage();
    }

    // Create and sort the league ladder
    List<LadderTeam> finalLadderTeams = ladderTeamsMap.values.toList();
    LeagueLadder leagueLadder =
        LeagueLadder(league: league, teams: finalLadderTeams);
    leagueLadder.sortLadder(); // Uses the sortLadder method from LeagueLadder

    // remove teams with 0 points, 0 played
    leagueLadder.teams
        .removeWhere((team) => team.points == 0 && team.played == 0);

    return leagueLadder;
  }
}
