import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/services/ladder_calculation_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Helper function to create a Team (makes test setup cleaner)
Team _createTeam(String dbkey, String name, League league) {
  return Team(dbkey: dbkey, name: name, league: league);
}

// Helper function to create a Game (makes test setup cleaner)
Game _createGame({
  required String dbkey,
  required League league,
  required Team homeTeam,
  required Team awayTeam,
  required DateTime startTime,
  int? homeScore,
  int? awayScore,
  int roundNumber = 1,
  int matchNumber = 1,
}) {
  Scoring? scoring;
  if (homeScore != null && awayScore != null) {
    scoring = Scoring(homeTeamScore: homeScore, awayTeamScore: awayScore);
  }
  return Game(
    dbkey: dbkey,
    league: league,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    location: 'Test Location',
    startTimeUTC: startTime,
    fixtureRoundNumber: roundNumber,
    fixtureMatchNumber: matchNumber,
    scoring: scoring,
  );
}

void main() {
  group('LadderCalculationService Tests', () {
    late LadderCalculationService service;
    // Define some teams for NRL
    final teamNrlA = _createTeam('nrl-teamA', 'NRL Team A', League.nrl);
    final teamNrlB = _createTeam('nrl-teamB', 'NRL Team B', League.nrl);
    // Define some teams for AFL
    final teamAflA = _createTeam('afl-teamA', 'AFL Team A', League.afl);
    final teamAflB = _createTeam('afl-teamB', 'AFL Team B', League.afl);
    final teamAflC = _createTeam('afl-teamC', 'AFL Team C', League.afl);

    setUp(() {
      service = LadderCalculationService();
    });

    test('should return an empty ladder if no games are provided', () {
      final ladder = service.calculateLadder(
        allGames: [],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );
      expect(ladder.teams.isEmpty, isTrue);
    });

    test('should return an empty ladder if no league teams are provided', () {
      final game1 = _createGame(
          dbkey: 'nrl-1-1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          homeScore: 10,
          awayScore: 0);
      final ladder = service.calculateLadder(
        allGames: [game1],
        leagueTeams: [],
        league: League.nrl,
      );
      expect(ladder.teams.isEmpty, isTrue);
    });

    test('should correctly calculate NRL ladder for a single home win', () {
      final game1 = _createGame(
        dbkey: 'nrl-1-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        homeScore: 12,
        awayScore: 6,
      );

      final ladder = service.calculateLadder(
        allGames: [game1],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );

      expect(ladder.teams.length, 2);
      final ladderTeamA =
          ladder.teams.firstWhere((t) => t.teamName == 'NRL Team A');
      final ladderTeamB =
          ladder.teams.firstWhere((t) => t.teamName == 'NRL Team B');

      // Team A (Winner)
      expect(ladderTeamA.played, 1);
      expect(ladderTeamA.won, 1);
      expect(ladderTeamA.lost, 0);
      expect(ladderTeamA.drawn, 0);
      expect(ladderTeamA.pointsFor, 12);
      expect(ladderTeamA.pointsAgainst, 6);
      expect(ladderTeamA.points, 2); // NRL: 2 points for a win
      expect(ladderTeamA.percentage, closeTo(200.0, 0.01));

      // Team B (Loser)
      expect(ladderTeamB.played, 1);
      expect(ladderTeamB.won, 0);
      expect(ladderTeamB.lost, 1);
      expect(ladderTeamB.drawn, 0);
      expect(ladderTeamB.pointsFor, 6);
      expect(ladderTeamB.pointsAgainst, 12);
      expect(ladderTeamB.points, 0);
      expect(ladderTeamB.percentage, closeTo(50.0, 0.01));

      // Check sorting (A should be above B)
      expect(ladder.teams.first.teamName, 'NRL Team A');
    });

    test(
        'should correctly calculate AFL ladder for a single away win and a draw',
        () {
      final game1 = _createGame(
        // Away win for teamAflB
        dbkey: 'afl-1-1', homeTeam: teamAflA, awayTeam: teamAflB,
        league: League.afl,
        startTime: DateTime.now().subtract(const Duration(days: 2)),
        homeScore: 60, awayScore: 90,
      );
      final game2 = _createGame(
        // Draw between teamAflA and teamAflC
        dbkey: 'afl-1-2', homeTeam: teamAflA, awayTeam: teamAflC,
        league: League.afl,
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        homeScore: 70, awayScore: 70,
      );

      final ladder = service.calculateLadder(
        allGames: [game1, game2],
        leagueTeams: [teamAflA, teamAflB, teamAflC],
        league: League.afl,
      );

      expect(ladder.teams.length, 3);
      final ltA = ladder.teams.firstWhere((t) => t.teamName == 'AFL Team A');
      final ltB = ladder.teams.firstWhere((t) => t.teamName == 'AFL Team B');
      final ltC = ladder.teams.firstWhere((t) => t.teamName == 'AFL Team C');

      // Team B (Won 1)
      expect(ltB.played, 1);
      expect(ltB.won, 1);
      expect(ltB.lost, 0);
      expect(ltB.drawn, 0);
      expect(ltB.pointsFor, 90);
      expect(ltB.pointsAgainst, 60);
      expect(ltB.points, 4); // AFL: 4 points for a win
      expect(ltB.percentage, closeTo(150.0, 0.01));

      // Team C (Drew 1)
      expect(ltC.played, 1);
      expect(ltC.won, 0);
      expect(ltC.lost, 0);
      expect(ltC.drawn, 1);
      expect(ltC.pointsFor, 70);
      expect(ltC.pointsAgainst, 70);
      expect(ltC.points, 2); // AFL: 2 points for a draw
      expect(ltC.percentage, closeTo(100.0, 0.01));

      // Team A (Lost 1, Drew 1)
      expect(ltA.played, 2);
      expect(ltA.won, 0);
      expect(ltA.lost, 1);
      expect(ltA.drawn, 1);
      expect(ltA.pointsFor, 130);
      expect(ltA.pointsAgainst, 160); // 60+70 For, 90+70 Against
      expect(ltA.points, 2); // AFL: 0 for loss, 2 for draw
      expect(ltA.percentage, closeTo((130 / 160) * 100, 0.01));

      // Check sorting: B (4pts), then C (2pts, 100%), then A (2pts, ~81.25%)
      expect(ladder.teams[0].teamName, 'AFL Team B');
      expect(ladder.teams[1].teamName, 'AFL Team C');
      expect(ladder.teams[2].teamName, 'AFL Team A');
    });

    test('should ignore games from other leagues', () {
      final nrlGame = _createGame(
          dbkey: 'nrl-1-1',
          homeTeam: teamNrlA,
          awayTeam: teamNrlB,
          league: League.nrl,
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          homeScore: 10,
          awayScore: 0);
      final aflLadder = service.calculateLadder(
        allGames: [nrlGame], // Game from NRL
        leagueTeams: [teamAflA, teamAflB], // AFL teams
        league: League.afl, // Requesting AFL ladder
      );
      expect(aflLadder.teams.every((team) => team.played == 0), isTrue);
    });

    test('should ignore games without scores', () {
      final gameNoScore = _createGame(
        dbkey: 'nrl-1-1', homeTeam: teamNrlA, awayTeam: teamNrlB,
        league: League.nrl,
        startTime:
            DateTime.now().subtract(const Duration(days: 1)), // No scores
      );
      final ladder = service.calculateLadder(
        allGames: [gameNoScore],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );
      expect(ladder.teams.every((team) => team.played == 0), isTrue);
    });

    // Add more tests for percentage edge cases, multiple games, complex sorting scenarios etc.
  });
}
