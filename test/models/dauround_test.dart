import 'package:test/test.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('DAURound Model Tests', () {
    late DateTime testStartTime;
    late DateTime testEndTime;
    late Game testGame;

    setUp(() {
      testStartTime = DateTime.utc(2024, 1, 15, 19, 0); // 7 PM UTC
      testEndTime = DateTime.utc(
        2024,
        1,
        17,
        21,
        30,
      ); // 9:30 PM UTC two days later

      final homeTeam = Team(
        dbkey: 'home',
        name: 'Home Team',
        league: League.nrl,
      );
      final awayTeam = Team(
        dbkey: 'away',
        name: 'Away Team',
        league: League.nrl,
      );

      testGame = Game(
        dbkey: 'test_game',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Test Stadium',
        startTimeUTC: testStartTime,
        league: League.nrl,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
    });

    group('Constructor and Properties', () {
      test('should create DAURound with required properties', () {
        final dauRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        expect(dauRound.dAUroundNumber, equals(1));
        expect(dauRound.firstGameKickOffUTC, equals(testStartTime));
        expect(dauRound.lastGameKickOffUTC, equals(testEndTime));
        expect(dauRound.games, isEmpty);
        expect(dauRound.roundState, equals(RoundState.notStarted));
        expect(dauRound.nrlGameCount, equals(0));
        expect(dauRound.aflGameCount, equals(0));
      });

      test('should create DAURound with optional admin override dates', () {
        final adminStartDate = DateTime.utc(2024, 1, 14, 12, 0);
        final adminEndDate = DateTime.utc(2024, 1, 18, 12, 0);

        final dauRound = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
          adminOverrideRoundStartDate: adminStartDate,
          adminOverrideRoundEndDate: adminEndDate,
        );

        expect(dauRound.adminOverrideRoundStartDate, equals(adminStartDate));
        expect(dauRound.adminOverrideRoundEndDate, equals(adminEndDate));
      });

      test('should create DAURound with initial games list', () {
        final dauRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
          games: [testGame],
        );

        expect(dauRound.games, hasLength(1));
        expect(dauRound.games.first, equals(testGame));
      });
    });

    group('Static Constants', () {
      test('should have correct static height values', () {
        expect(DAURound.leagueHeaderHeight, equals(103));
        expect(DAURound.leagueHeaderEndedHeight, equals(104));
        expect(DAURound.noGamesCardHeight, equals(75));
      });

      test('static heights should be reasonable UI values', () {
        expect(DAURound.leagueHeaderHeight, greaterThan(50));
        expect(DAURound.leagueHeaderHeight, lessThan(200));
        expect(DAURound.leagueHeaderEndedHeight, greaterThan(50));
        expect(DAURound.leagueHeaderEndedHeight, lessThan(200));
        expect(DAURound.noGamesCardHeight, greaterThan(30));
        expect(DAURound.noGamesCardHeight, lessThan(150));
      });
    });

    group('JSON Factory Constructor', () {
      test('should create DAURound from JSON data', () {
        final jsonData = {
          'roundStartDate': '2024-01-15T19:00:00.000Z',
          'roundEndDate': '2024-01-17T21:30:00.000Z',
        };

        final dauRound = DAURound.fromJson(jsonData, 3);

        expect(dauRound.dAUroundNumber, equals(3));
        expect(
          dauRound.firstGameKickOffUTC,
          equals(DateTime.parse('2024-01-15T19:00:00.000Z')),
        );
        expect(
          dauRound.lastGameKickOffUTC,
          equals(DateTime.parse('2024-01-17T21:30:00.000Z')),
        );
      });

      test('should handle ISO8601 date formats correctly', () {
        final jsonData = {
          'roundStartDate': '2024-03-01T15:30:00.000Z',
          'roundEndDate': '2024-03-03T18:45:00.000Z',
        };

        final dauRound = DAURound.fromJson(jsonData, 5);

        expect(dauRound.firstGameKickOffUTC.year, equals(2024));
        expect(dauRound.firstGameKickOffUTC.month, equals(3));
        expect(dauRound.firstGameKickOffUTC.day, equals(1));
        expect(dauRound.firstGameKickOffUTC.hour, equals(15));
        expect(dauRound.firstGameKickOffUTC.minute, equals(30));

        expect(dauRound.lastGameKickOffUTC.year, equals(2024));
        expect(dauRound.lastGameKickOffUTC.month, equals(3));
        expect(dauRound.lastGameKickOffUTC.day, equals(3));
        expect(dauRound.lastGameKickOffUTC.hour, equals(18));
        expect(dauRound.lastGameKickOffUTC.minute, equals(45));
      });
    });

    group('RoundState Enum', () {
      test('should have all expected round states', () {
        expect(RoundState.values, contains(RoundState.notStarted));
        expect(RoundState.values, contains(RoundState.started));
        expect(RoundState.values, contains(RoundState.allGamesEnded));
        expect(RoundState.values, contains(RoundState.noGames));
        expect(RoundState.values, hasLength(4));
      });

      test('should initialize with notStarted state', () {
        final dauRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        expect(dauRound.roundState, equals(RoundState.notStarted));
      });
    });

    group('Comparable Interface', () {
      test('should implement Comparable for sorting', () {
        final round1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        final round2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: testStartTime.add(const Duration(days: 7)),
          lastGameKickOffUTC: testEndTime.add(const Duration(days: 7)),
        );

        final round3 = DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: testStartTime.add(const Duration(days: 14)),
          lastGameKickOffUTC: testEndTime.add(const Duration(days: 14)),
        );

        final rounds = [round3, round1, round2];
        rounds.sort();

        expect(rounds[0].dAUroundNumber, equals(1));
        expect(rounds[1].dAUroundNumber, equals(2));
        expect(rounds[2].dAUroundNumber, equals(3));
      });

      test('should handle rounds with same round number', () {
        final round1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        final round1Duplicate = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime.add(const Duration(hours: 1)),
          lastGameKickOffUTC: testEndTime.add(const Duration(hours: 1)),
        );

        expect(round1.compareTo(round1Duplicate), equals(0));
      });
    });

    group('Game Counts', () {
      test('should initialize game counts to zero', () {
        final dauRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        expect(dauRound.nrlGameCount, equals(0));
        expect(dauRound.aflGameCount, equals(0));
      });

      test('should allow modification of game counts', () {
        final dauRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        dauRound.nrlGameCount = 8;
        dauRound.aflGameCount = 9;

        expect(dauRound.nrlGameCount, equals(8));
        expect(dauRound.aflGameCount, equals(9));
      });
    });

    group('Edge Cases and Validation', () {
      test('should handle round where end time is before start time', () {
        final invalidRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: testEndTime, // End time as start
          lastGameKickOffUTC: testStartTime, // Start time as end
        );

        expect(
          invalidRound.firstGameKickOffUTC.isAfter(
            invalidRound.lastGameKickOffUTC,
          ),
          isTrue,
        );
      });

      test('should handle extreme round numbers', () {
        final highRoundNumber = DAURound(
          dAUroundNumber: 999,
          firstGameKickOffUTC: testStartTime,
          lastGameKickOffUTC: testEndTime,
        );

        expect(highRoundNumber.dAUroundNumber, equals(999));
      });

      test('should handle dates far in the future', () {
        final futureStart = DateTime.utc(2099, 12, 25, 12, 0);
        final futureEnd = DateTime.utc(2099, 12, 27, 12, 0);

        final futureRound = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: futureStart,
          lastGameKickOffUTC: futureEnd,
        );

        expect(futureRound.firstGameKickOffUTC.year, equals(2099));
        expect(futureRound.lastGameKickOffUTC.year, equals(2099));
      });
    });
  });
}
