import 'package:test/test.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/models/team.dart';

void main() {
  group('Tip Model Tests', () {
    late Tipper testTipper;
    late Game testGame;
    late Scoring testScoring;
    late DateTime testDateTime;
    late Team homeTeam;
    late Team awayTeam;

    setUp(() {
      testDateTime = DateTime.utc(2024, 1, 15, 14, 30);

      testTipper = Tipper(
        dbkey: 'tipper1',
        name: 'Test Tipper',
        email: 'test@example.com',
        tipperRole: TipperRole.tipper,
        authuid: 'uid123',
        compsPaidFor: [],
      );

      homeTeam = Team(
        dbkey: 'home_team',
        name: 'Home Team',
        league: League.nrl,
      );

      awayTeam = Team(
        dbkey: 'away_team',
        name: 'Away Team',
        league: League.nrl,
      );

      testScoring = Scoring(homeTeamScore: 24, awayTeamScore: 18);

      testGame = Game(
        dbkey: 'game1',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Test Stadium',
        startTimeUTC: testDateTime,
        league: League.nrl,
        scoring: testScoring,
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );
    });

    group('Constructor and Properties', () {
      test('should create tip with all required properties', () {
        final tip = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        expect(tip.dbkey, equals('tip1'));
        expect(tip.game, equals(testGame));
        expect(tip.tipper, equals(testTipper));
        expect(tip.tip, equals(GameResult.a));
        expect(tip.submittedTimeUTC, equals(testDateTime));
      });

      test('should create tip with null dbkey', () {
        final tip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: testDateTime,
        );

        expect(tip.dbkey, isNull);
        expect(tip.game, equals(testGame));
        expect(tip.tipper, equals(testTipper));
        expect(tip.tip, equals(GameResult.b));
      });
    });

    group('isDefaultTip', () {
      test('should return true for default tip with epoch zero time', () {
        final defaultTime = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
        final tip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.z,
          submittedTimeUTC: defaultTime,
        );

        expect(tip.isDefaultTip(), isTrue);
      });

      test('should return false for tip with actual submitted time', () {
        final tip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        expect(tip.isDefaultTip(), isFalse);
      });

      test('should return false for tip with current time', () {
        final tip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.c,
          submittedTimeUTC: DateTime.now().toUtc(),
        );

        expect(tip.isDefaultTip(), isFalse);
      });
    });

    group('JSON Serialization', () {
      test('should create tip from JSON correctly', () {
        final jsonData = {
          'gameResult': 'a',
          'submittedTimeUTC': '2024-01-15T14:30:00.000Z',
        };

        final tip = Tip.fromJson(jsonData, 'tip1', testTipper, testGame);

        expect(tip.dbkey, equals('tip1'));
        expect(tip.game, equals(testGame));
        expect(tip.tipper, equals(testTipper));
        expect(tip.tip, equals(GameResult.a));
        expect(
          tip.submittedTimeUTC,
          equals(DateTime.parse('2024-01-15T14:30:00.000Z')),
        );
      });

      test('should handle all game results in fromJson', () {
        for (final gameResult in GameResult.values) {
          final jsonData = {
            'gameResult': gameResult.name,
            'submittedTimeUTC': '2024-01-15T14:30:00.000Z',
          };

          final tip = Tip.fromJson(jsonData, 'tip1', testTipper, testGame);
          expect(tip.tip, equals(gameResult));
        }
      });

      test('should convert tip to JSON correctly', () {
        final tip = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: testDateTime,
        );

        final json = tip.toJson();

        expect(json['gameResult'], equals('b'));
        expect(json['submittedTimeUTC'], equals(testDateTime.toString()));
        expect(json.keys.length, equals(2));
      });

      test('should handle round-trip JSON conversion', () {
        final originalTip = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.d,
          submittedTimeUTC: testDateTime,
        );

        final json = originalTip.toJson();
        final reconstructedTip = Tip.fromJson(
          json,
          'tip1',
          testTipper,
          testGame,
        );

        expect(reconstructedTip.tip, equals(originalTip.tip));
        expect(
          reconstructedTip.submittedTimeUTC,
          equals(originalTip.submittedTimeUTC),
        );
      });
    });

    group('getGameResultText', () {
      test('should return NRL text for NRL game', () {
        final nrlHomeTeam = Team(
          dbkey: 'broncos',
          name: 'Broncos',
          league: League.nrl,
        );
        final nrlAwayTeam = Team(
          dbkey: 'cowboys',
          name: 'Cowboys',
          league: League.nrl,
        );

        final nrlGame = Game(
          dbkey: 'nrl_game',
          homeTeam: nrlHomeTeam,
          awayTeam: nrlAwayTeam,
          location: 'Suncorp Stadium',
          startTimeUTC: testDateTime,
          league: League.nrl,
          scoring: testScoring,
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );

        final tip = Tip(
          game: nrlGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final resultText = tip.getGameResultText();
        expect(resultText, isA<String>());
        expect(resultText, isNotEmpty);
      });

      test('should return AFL text for AFL game', () {
        final aflHomeTeam = Team(
          dbkey: 'hawks',
          name: 'Hawks',
          league: League.afl,
        );
        final aflAwayTeam = Team(
          dbkey: 'blues',
          name: 'Blues',
          league: League.afl,
        );

        final aflGame = Game(
          dbkey: 'afl_game',
          homeTeam: aflHomeTeam,
          awayTeam: aflAwayTeam,
          location: 'MCG',
          startTimeUTC: testDateTime,
          league: League.afl,
          scoring: testScoring,
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );

        final tip = Tip(
          game: aflGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: testDateTime,
        );

        final resultText = tip.getGameResultText();
        expect(resultText, isA<String>());
        expect(resultText, isNotEmpty);
      });
    });

    group('Equality and Comparison', () {
      test('should be equal when all properties match', () {
        final tip1 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final tip2 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        expect(tip1, equals(tip2));
        expect(tip1.hashCode, equals(tip2.hashCode));
      });

      test('should not be equal when dbkey differs', () {
        final tip1 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final tip2 = Tip(
          dbkey: 'tip2',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        expect(tip1, isNot(equals(tip2)));
      });

      test('should not be equal when game result differs', () {
        final tip1 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final tip2 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: testDateTime,
        );

        expect(tip1, isNot(equals(tip2)));
      });

      test('should not be equal when submitted time differs', () {
        final tip1 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final tip2 = Tip(
          dbkey: 'tip1',
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime.add(const Duration(hours: 1)),
        );

        expect(tip1, isNot(equals(tip2)));
      });
    });

    group('Comparable interface', () {
      test('should sort tips by submitted time ascending', () {
        final time1 = DateTime.utc(2024, 1, 15, 10, 0);
        final time2 = DateTime.utc(2024, 1, 15, 12, 0);
        final time3 = DateTime.utc(2024, 1, 15, 14, 0);

        final tip1 = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: time2, // Middle time
        );

        final tip2 = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: time1, // Earliest time
        );

        final tip3 = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.c,
          submittedTimeUTC: time3, // Latest time
        );

        final tips = [tip1, tip2, tip3];
        tips.sort();

        expect(tips[0], equals(tip2)); // Earliest first
        expect(tips[1], equals(tip1)); // Middle second
        expect(tips[2], equals(tip3)); // Latest last
      });

      test('should handle tips with same submitted time', () {
        final tip1 = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: testDateTime,
        );

        final tip2 = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: testDateTime,
        );

        expect(tip1.compareTo(tip2), equals(0));
      });
    });

    group('Edge Cases', () {
      test('should handle tip with null scoring in game', () {
        final teamA = Team(dbkey: 'team_a', name: 'Team A', league: League.nrl);
        final teamB = Team(dbkey: 'team_b', name: 'Team B', league: League.nrl);

        final gameWithoutScoring = Game(
          dbkey: 'game_no_scoring',
          homeTeam: teamA,
          awayTeam: teamB,
          location: 'Stadium',
          startTimeUTC: testDateTime,
          league: League.nrl,
          scoring: null,
          fixtureRoundNumber: 1,
          fixtureMatchNumber: 1,
        );

        final tip = Tip(
          game: gameWithoutScoring,
          tipper: testTipper,
          tip: GameResult.z,
          submittedTimeUTC: testDateTime,
        );

        // This tests that the tip can be created, but getGameResultText and score methods
        // would throw exceptions when called (as expected)
        expect(tip.game.scoring, isNull);
        expect(() => tip.getGameResultText(), throwsA(isA<TypeError>()));
      });

      test('should handle tips with extreme dates', () {
        final farFutureDate = DateTime.utc(2099, 12, 31, 23, 59, 59);
        final farPastDate = DateTime.utc(1900, 1, 1, 0, 0, 0);

        final futureTip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.a,
          submittedTimeUTC: farFutureDate,
        );

        final pastTip = Tip(
          game: testGame,
          tipper: testTipper,
          tip: GameResult.b,
          submittedTimeUTC: farPastDate,
        );

        expect(futureTip.submittedTimeUTC, equals(farFutureDate));
        expect(pastTip.submittedTimeUTC, equals(farPastDate));
        expect(futureTip.compareTo(pastTip), greaterThan(0));
      });
    });
  });
}
