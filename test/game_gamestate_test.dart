/* import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:test/test.dart';
import 'package:daufootytipping/models/game.dart';

void main() {
  group('gameState', () {
    test(
        'returns GameState.startingSoon when current time is within 14 hours of game start time',
        () {
      final game = Game(
          startTimeUTC: DateTime.now().add(const Duration(hours: 1)).toUtc(),
          league: League.afl,
          scoring: null,
          dbkey: '1',
          dauRound: DAURound(
              roundEndDate: DateTime.now(),
              roundStartDate: DateTime.now(),
              dAUroundNumber: 1,
              //roundState: RoundState.noGames,
              gamesAsKeys: ['nrl-01-01']),
          homeTeam: Team(dbkey: '1', name: 'Team A', league: League.afl),
          awayTeam: Team(dbkey: '2', name: 'Team B', league: League.afl),
          location: 'location',
          locationLatLong: null,
          roundNumber: 1,
          matchNumber: 1);
      expect(game.gameState, equals(GameState.startingSoon));
    });

    test(
        'returns GameState.notStarted when game start time is more than 15 hours away',
        () {
      final game = Game(
          startTimeUTC: DateTime.now().add(const Duration(hours: 15)).toUtc(),
          league: League.afl,
          scoring: null,
          dbkey: '1',
          dauRound: DAURound(
              roundEndDate: DateTime.now(),
              roundStartDate: DateTime.now(),
              dAUroundNumber: 1,
              //roundStarted: true,
              gamesAsKeys: ['nrl-01-01']),
          homeTeam: Team(dbkey: '1', name: 'Team A', league: League.afl),
          awayTeam: Team(dbkey: '2', name: 'Team B', league: League.afl),
          location: 'location',
          locationLatLong: null,
          roundNumber: 1,
          matchNumber: 1);
      expect(game.gameState, equals(GameState.notStarted));
    });

    test(
        'returns GameState.resultKnown if game start is in the past and scoring is available',
        () {
      final game = Game(
          startTimeUTC:
              DateTime.now().subtract(const Duration(hours: 12)).toUtc(),
          league: League.afl,
          scoring: Scoring(homeTeamScore: 10, awayTeamScore: 20),
          dbkey: '1',
          dauRound: DAURound(
              roundEndDate: DateTime.now(),
              roundStartDate: DateTime.now(),
              dAUroundNumber: 1,
              //roundStarted: true,
              gamesAsKeys: ['nrl-01-01']),
          homeTeam: Team(dbkey: '1', name: 'Team A', league: League.afl),
          awayTeam: Team(dbkey: '2', name: 'Team B', league: League.afl),
          location: 'location',
          locationLatLong: null,
          roundNumber: 1,
          matchNumber: 1);
      expect(game.gameState, equals(GameState.startedResultKnown));
    });

    test(
        'returns GameState.resultNotKnown when game start time is in the past and scoring is not available',
        () {
      final game = Game(
          startTimeUTC:
              DateTime.now().subtract(const Duration(hours: 3)).toUtc(),
          league: League.afl,
          scoring: null,
          dbkey: '1',
          dauRound: DAURound(
              roundEndDate: DateTime.now(),
              roundStartDate: DateTime.now(),
              dAUroundNumber: 1,
              //roundStarted: true,
              gamesAsKeys: ['nrl-01-01']),
          homeTeam: Team(dbkey: '1', name: 'Team A', league: League.afl),
          awayTeam: Team(dbkey: '2', name: 'Team B', league: League.afl),
          location: 'location',
          locationLatLong: null,
          roundNumber: 1,
          matchNumber: 1);
      expect(game.gameState, equals(GameState.startedResultNotKnown));
    });
  });
}
 */