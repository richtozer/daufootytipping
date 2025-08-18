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

    test('should return null if no games are provided', () {
      final ladder = service.calculateLadder(
        allGames: [],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );
      expect(ladder, isNull);
    });

    test('should return null if no league teams are provided', () {
      final game1 = _createGame(
        dbkey: 'nrl-1-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        homeScore: 10,
        awayScore: 0,
      );
      final ladder = service.calculateLadder(
        allGames: [game1],
        leagueTeams: [],
        league: League.nrl,
      );
      expect(ladder, isNull);
    });

    test('should correctly calculate NRL ladder for multiple rounds', () {
      // Create games across 3 rounds to satisfy the minimum requirement
      final game1 = _createGame(
        dbkey: 'nrl-1-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 3)),
        homeScore: 12,
        awayScore: 6,
        roundNumber: 1,
      );

      final game2 = _createGame(
        dbkey: 'nrl-2-1',
        homeTeam: teamNrlB,
        awayTeam: teamNrlA,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 2)),
        homeScore: 8,
        awayScore: 14,
        roundNumber: 2,
      );

      final game3 = _createGame(
        dbkey: 'nrl-3-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        homeScore: 10,
        awayScore: 10,
        roundNumber: 3,
      );

      final ladder = service.calculateLadder(
        allGames: [game1, game2, game3],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );

      expect(ladder?.teams.length, 2);
      final ladderTeamA = ladder?.teams.firstWhere(
        (t) => t.teamName == 'NRL Team A',
      );
      final ladderTeamB = ladder?.teams.firstWhere(
        (t) => t.teamName == 'NRL Team B',
      );

      // Team A (Won 2, Drew 1)
      expect(ladderTeamA?.played, 3);
      expect(ladderTeamA?.won, 2);
      expect(ladderTeamA?.lost, 0);
      expect(ladderTeamA?.drawn, 1);
      expect(ladderTeamA?.pointsFor, 36); // 12 + 14 + 10
      expect(ladderTeamA?.pointsAgainst, 24); // 6 + 8 + 10
      expect(ladderTeamA?.points, 5); // NRL: 2 + 2 + 1 = 5 points
      expect(ladderTeamA?.percentage, closeTo(150.0, 0.01));

      // Team B (Lost 2, Drew 1)
      expect(ladderTeamB?.played, 3);
      expect(ladderTeamB?.won, 0);
      expect(ladderTeamB?.lost, 2);
      expect(ladderTeamB?.drawn, 1);
      expect(ladderTeamB?.pointsFor, 24); // 6 + 8 + 10
      expect(ladderTeamB?.pointsAgainst, 36); // 12 + 14 + 10
      expect(ladderTeamB?.points, 1); // NRL: 0 + 0 + 1 = 1 point
      expect(ladderTeamB?.percentage, closeTo(66.67, 0.1));

      // Check sorting (A should be above B)
      expect(ladder?.teams.first.teamName, 'NRL Team A');
    });

    test(
      'should correctly calculate AFL ladder for multiple rounds with wins and draws',
      () {
        // Round 1 games
        final game1 = _createGame(
          dbkey: 'afl-1-1',
          homeTeam: teamAflA,
          awayTeam: teamAflB,
          league: League.afl,
          startTime: DateTime.now().subtract(const Duration(days: 4)),
          homeScore: 60,
          awayScore: 90,
          roundNumber: 1,
        );
        final game2 = _createGame(
          dbkey: 'afl-1-2',
          homeTeam: teamAflA,
          awayTeam: teamAflC,
          league: League.afl,
          startTime: DateTime.now().subtract(const Duration(days: 3)),
          homeScore: 70,
          awayScore: 70,
          roundNumber: 1,
        );

        // Round 2 games
        final game3 = _createGame(
          dbkey: 'afl-2-1',
          homeTeam: teamAflB,
          awayTeam: teamAflC,
          league: League.afl,
          startTime: DateTime.now().subtract(const Duration(days: 2)),
          homeScore: 85,
          awayScore: 75,
          roundNumber: 2,
        );

        // Round 3 games
        final game4 = _createGame(
          dbkey: 'afl-3-1',
          homeTeam: teamAflC,
          awayTeam: teamAflA,
          league: League.afl,
          startTime: DateTime.now().subtract(const Duration(days: 1)),
          homeScore: 80,
          awayScore: 65,
          roundNumber: 3,
        );

        final ladder = service.calculateLadder(
          allGames: [game1, game2, game3, game4],
          leagueTeams: [teamAflA, teamAflB, teamAflC],
          league: League.afl,
        );

        expect(ladder?.teams.length, 3);
        final ltA = ladder?.teams.firstWhere((t) => t.teamName == 'AFL Team A');
        final ltB = ladder?.teams.firstWhere((t) => t.teamName == 'AFL Team B');
        final ltC = ladder?.teams.firstWhere((t) => t.teamName == 'AFL Team C');

        // Team B (Won 2)
        expect(ltB?.played, 2);
        expect(ltB?.won, 2);
        expect(ltB?.lost, 0);
        expect(ltB?.drawn, 0);
        expect(ltB?.pointsFor, 175); // 90 + 85
        expect(ltB?.pointsAgainst, 135); // 60 + 75
        expect(ltB?.points, 8); // AFL: 4 + 4 = 8 points
        expect(ltB?.percentage, closeTo((175 / 135) * 100, 0.1));

        // Team C (Won 1, Lost 1, Drew 1)
        expect(ltC?.played, 3);
        expect(ltC?.won, 1);
        expect(ltC?.lost, 1);
        expect(ltC?.drawn, 1);
        expect(ltC?.pointsFor, 225); // 70 + 75 + 80
        expect(ltC?.pointsAgainst, 220); // 70 + 85 + 65
        expect(ltC?.points, 6); // AFL: 2 + 0 + 4 = 6 points
        expect(ltC?.percentage, closeTo((225 / 220) * 100, 0.1));

        // Team A (Lost 2, Drew 1)
        expect(ltA?.played, 3);
        expect(ltA?.won, 0);
        expect(ltA?.lost, 2);
        expect(ltA?.drawn, 1);
        expect(ltA?.pointsFor, 195); // 60 + 70 + 65
        expect(ltA?.pointsAgainst, 240); // 90 + 70 + 80
        expect(ltA?.points, 2); // AFL: 0 + 2 + 0 = 2 points
        expect(ltA?.percentage, closeTo((195 / 240) * 100, 0.1));

        // Check sorting: B (8pts), then C (6pts), then A (2pts)
        expect(ladder?.teams[0].teamName, 'AFL Team B');
        expect(ladder?.teams[1].teamName, 'AFL Team C');
        expect(ladder?.teams[2].teamName, 'AFL Team A');
      },
    );

    test('should return null when requesting ladder for different league', () {
      final nrlGame = _createGame(
        dbkey: 'nrl-1-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(const Duration(days: 1)),
        homeScore: 10,
        awayScore: 0,
      );
      final aflLadder = service.calculateLadder(
        allGames: [nrlGame], // Game from NRL
        leagueTeams: [teamAflA, teamAflB], // AFL teams
        league: League.afl, // Requesting AFL ladder
      );
      expect(aflLadder, isNull); // No completed AFL rounds, so null
    });

    test('should return null when games have no scores', () {
      final gameNoScore = _createGame(
        dbkey: 'nrl-1-1',
        homeTeam: teamNrlA,
        awayTeam: teamNrlB,
        league: League.nrl,
        startTime: DateTime.now().subtract(
          const Duration(days: 1),
        ), // No scores
      );
      final ladder = service.calculateLadder(
        allGames: [gameNoScore],
        leagueTeams: [teamNrlA, teamNrlB],
        league: League.nrl,
      );
      expect(ladder, isNull); // No completed rounds with scores, so null
    });

    // Add more tests for percentage edge cases, multiple games, complex sorting scenarios etc.

    test('should correctly award 2 points for an NRL bye', () {
      final teamNrlC = _createTeam('nrl-teamC', 'NRL Team C', League.nrl);
      // 3 rounds of games, where each team has one bye
      final allGames = [
        // Round 1 (C has a bye)
        _createGame(
            dbkey: 'nrl-1-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 3)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 1),
        // Round 2 (B has a bye)
        _createGame(
            dbkey: 'nrl-2-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlC,
            startTime: DateTime.now().subtract(const Duration(days: 2)),
            homeScore: 10,
            awayScore: 20,
            roundNumber: 2),
        // Round 3 (A has a bye)
        _createGame(
            dbkey: 'nrl-3-1',
            league: League.nrl,
            homeTeam: teamNrlB,
            awayTeam: teamNrlC,
            startTime: DateTime.now().subtract(const Duration(days: 1)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 3),
      ];

      final ladder = service.calculateLadder(
        allGames: allGames,
        leagueTeams: [teamNrlA, teamNrlB, teamNrlC],
        league: League.nrl,
      );

      expect(ladder, isNotNull);
      final ltA = ladder!.teams.firstWhere((t) => t.teamName == 'NRL Team A');
      final ltB = ladder.teams.firstWhere((t) => t.teamName == 'NRL Team B');
      final ltC = ladder.teams.firstWhere((t) => t.teamName == 'NRL Team C');

      // Team A: 1 win, 1 loss, 1 bye = 2 + 0 + 2 = 4 points
      expect(ltA.byes, 1);
      expect(ltA.points, 4);
      // Team B: 1 win, 1 loss, 1 bye = 2 + 0 + 2 = 4 points
      expect(ltB.byes, 1);
      expect(ltB.points, 4);
      // Team C: 1 win, 1 loss, 1 bye = 2 + 0 + 2 = 4 points
      expect(ltC.byes, 1);
      expect(ltC.points, 4);

      // Check played count (should not include byes)
      expect(ltA.played, 2);
      expect(ltB.played, 2);
      expect(ltC.played, 2);
    });

    test('should not award byes for a round that is not yet fully past', () {
      final teamNrlC = _createTeam('nrl-teamC', 'NRL Team C', League.nrl);
      final allGames = [
        _createGame(
            dbkey: 'nrl-1-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 10)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 1),
        _createGame(
            dbkey: 'nrl-2-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlC,
            startTime: DateTime.now().subtract(const Duration(days: 9)),
            homeScore: 10,
            awayScore: 20,
            roundNumber: 2),
        _createGame(
            dbkey: 'nrl-3-1',
            league: League.nrl,
            homeTeam: teamNrlB,
            awayTeam: teamNrlC,
            startTime: DateTime.now().subtract(const Duration(days: 8)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 3),
        // Round 4 is in the future, so C's bye should not be counted
        _createGame(
            dbkey: 'nrl-4-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().add(const Duration(days: 1)),
            roundNumber: 4),
      ];

      final ladder = service.calculateLadder(
        allGames: allGames,
        leagueTeams: [teamNrlA, teamNrlB, teamNrlC],
        league: League.nrl,
      );

      expect(ladder, isNotNull);
      final ltC = ladder!.teams.firstWhere((t) => t.teamName == 'NRL Team C');
      // Team C has a bye in round 1 (completed) and round 4 (future)
      // Only the bye from round 1 should be counted.
      expect(ltC.byes, 1);
      expect(ltC.points, 4); // 2 from bye, 2 from win
      expect(ltC.played, 2);
    });

    test('should ignore "To be announced" teams in ladder calculation', () {
      final dummyTeam =
          _createTeam('nrl-tba', 'To be announced', League.nrl);
      final allGames = [
        _createGame(
            dbkey: 'nrl-1-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 3)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 1),
        _createGame(
            dbkey: 'nrl-2-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 2)),
            homeScore: 10,
            awayScore: 20,
            roundNumber: 2),
        _createGame(
            dbkey: 'nrl-3-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 1)),
            homeScore: 10,
            awayScore: 10,
            roundNumber: 3),
      ];
      final ladder = service.calculateLadder(
        allGames: allGames,
        leagueTeams: [teamNrlA, teamNrlB, dummyTeam],
        league: League.nrl,
      );
      expect(ladder, isNotNull);
      expect(ladder?.teams.length, 2);
      final hasDummyTeam =
          ladder!.teams.any((t) => t.teamName == 'To be announced');
      expect(hasDummyTeam, isFalse);
    });

    test('should exclude games after the cutoff date', () {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 2));
      final allGames = [
        // 3 completed rounds before cutoff
        _createGame(
            dbkey: 'nrl-1-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 5)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 1),
        _createGame(
            dbkey: 'nrl-2-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 4)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 2),
        _createGame(
            dbkey: 'nrl-3-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 3)),
            homeScore: 10,
            awayScore: 0,
            roundNumber: 3),
        // This game is after cutoff, should be excluded
        _createGame(
            dbkey: 'nrl-4-1',
            league: League.nrl,
            homeTeam: teamNrlA,
            awayTeam: teamNrlB,
            startTime: DateTime.now().subtract(const Duration(days: 1)),
            homeScore: 10,
            awayScore: 10,
            roundNumber: 4),
      ];

      final ladder = service.calculateLadder(
          allGames: allGames,
          leagueTeams: [teamNrlA, teamNrlB],
          league: League.nrl,
          cutoffDate: cutoffDate);

      // Ladder should be calculated, but only with games before the cutoff.
      expect(ladder, isNotNull);
      expect(ladder?.teams.length, 2);
      final ladderTeamA = ladder!.teams.firstWhere((t) => t.teamName == 'NRL Team A');
      // Team A won 3 games before the cutoff.
      expect(ladderTeamA.won, 3);
      expect(ladderTeamA.played, 3);
    });
  });
}
