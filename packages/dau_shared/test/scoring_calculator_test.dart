import 'package:test/test.dart';
import 'package:dau_shared/dau_shared.dart';

void main() {
  group('ScoringCalculator - calculateRoundStatsForTipper', () {
    final homeTeam = Team(dbkey: 'NRL-home', name: 'Home Team', league: League.nrl);
    final awayTeam = Team(dbkey: 'NRL-away', name: 'Away Team', league: League.nrl);
    final tipper = Tipper(
      dbkey: 'tipper-1',
      authuid: 'auth-1',
      email: 'tipper1@example.com',
      name: 'Tipper One',
      tipperRole: TipperRole.tipper,
      compsPaidFor: [],
    );

    test('should count outstanding tips for unsubmitted/missing tips', () {
      final now = DateTime.utc(2026, 5, 25, 12, 0);
      final game1 = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: DateTime.utc(2026, 5, 25, 14, 0), // Not started
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      final game2 = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: DateTime.utc(2026, 5, 25, 14, 0), // Not started
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
      );

      final stats = ScoringCalculator.calculateRoundStatsForTipper(
        roundNumber: 1,
        games: [game1, game2],
        tipsByGameKey: {},
        now: now,
      );

      expect(stats.nrlTipsOutstanding, equals(1));
      expect(stats.aflTipsOutstanding, equals(1));
      expect(stats.nrlPoints, equals(0));
      expect(stats.aflPoints, equals(0));
    });

    test('should calculate correct points for completed games', () {
      final now = DateTime.utc(2026, 5, 25, 18, 0);

      // Game started/finished
      final gameNrl = Game(
        dbkey: 'nrl-01-001',
        league: League.nrl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: DateTime.utc(2026, 5, 25, 10, 0), // Ended
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: Scoring(
          homeTeamScore: 25,
          awayTeamScore: 12,
        ),
      );

      final gameAfl = Game(
        dbkey: 'afl-01-001',
        league: League.afl,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        location: 'Stadium',
        startTimeUTC: DateTime.utc(2026, 5, 25, 10, 0), // Ended
        fixtureRoundNumber: 1,
        fixtureMatchNumber: 1,
        scoring: Scoring(
          homeTeamScore: 100,
          awayTeamScore: 80,
        ),
      );

      // Tipper tipped home margin for NRL (GameResult.a)
      final tipNrl = Tip(
        dbkey: 'tip-nrl',
        game: gameNrl,
        tipper: tipper,
        tip: GameResult.a, // Home margin
        submittedTimeUTC: DateTime.utc(2026, 5, 25, 9, 0),
      );

      // Tipper tipped draw for AFL (GameResult.c)
      final tipAfl = Tip(
        dbkey: 'tip-afl',
        game: gameAfl,
        tipper: tipper,
        tip: GameResult.c, // Draw
        submittedTimeUTC: DateTime.utc(2026, 5, 25, 9, 0),
      );

      final stats = ScoringCalculator.calculateRoundStatsForTipper(
        roundNumber: 1,
        games: [gameNrl, gameAfl],
        tipsByGameKey: {
          'nrl-01-001': tipNrl,
          'afl-01-001': tipAfl,
        },
        now: now,
      );

      // NRL points: Result is Home Margin (since 25 - 12 = 13 points difference, margin is >= 13).
      // Tipping GameResult.a correct. Points: 2 (correct tip) + 2 (margin tip matched) = 4.
      expect(stats.nrlPoints, equals(4));
      expect(stats.nrlMaxPoints, equals(4));
      expect(stats.nrlMarginTips, equals(1));
      expect(stats.nrlMarginUPS, equals(1));

      // AFL points: Result is Home (since 100 - 80 = 20 points difference, margin in AFL doesn't apply to tips or does it? AFL home is Result.b, difference is not draw).
      // Tipper tipped draw (Result.c).
      // Scoring should return 0 points for AFL tip. Max points possible is 2 (since result is home, tip points for correct result is 2).
      expect(stats.aflPoints, equals(0));
      expect(stats.aflMaxPoints, equals(2));
      expect(stats.aflMarginTips, equals(0));
      expect(stats.aflMarginUPS, equals(0));
    });
  });

  group('ScoringCalculator - calculateGameStatsEntry', () {
    final tipper1 = Tipper(
      dbkey: 't1',
      authuid: 'auth-1',
      email: 't1@example.com',
      name: 'T1',
      tipperRole: TipperRole.tipper,
      compsPaidFor: [],
    );
    final tipper2 = Tipper(
      dbkey: 't2',
      authuid: 'auth-2',
      email: 't2@example.com',
      name: 'T2',
      tipperRole: TipperRole.tipper,
      compsPaidFor: [],
    );
    final tipper3 = Tipper(
      dbkey: 't3',
      authuid: 'auth-3',
      email: 't3@example.com',
      name: 'T3',
      tipperRole: TipperRole.tipper,
      compsPaidFor: [],
    );

    final game = Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'NRL-home', name: 'Home Team', league: League.nrl),
      awayTeam: Team(dbkey: 'NRL-away', name: 'Away Team', league: League.nrl),
      location: 'Stadium',
      startTimeUTC: DateTime.utc(2026, 5, 25, 10, 0),
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
      scoring: Scoring(homeTeamScore: 25, awayTeamScore: 12),
    );

    test('should throw ArgumentError if input lists have different lengths', () {
      expect(
        () => ScoringCalculator.calculateGameStatsEntry(
          cohortTippers: [tipper1],
          tipsForCohort: [],
          league: League.nrl,
        ),
        throwsArgumentError,
      );
    });

    test('should compute correct distribution percentages and average points', () {
      final tip1 = Tip(
        dbkey: 'tip-1',
        game: game,
        tipper: tipper1,
        tip: GameResult.a, // Home margin
        submittedTimeUTC: DateTime.utc(2026, 5, 25, 9, 0),
      );

      final tip2 = Tip(
        dbkey: 'tip-2',
        game: game,
        tipper: tipper2,
        tip: GameResult.d, // Away
        submittedTimeUTC: DateTime.utc(2026, 5, 25, 9, 0),
      );

      // Tipper 3 did not tip (null)
      final stats = ScoringCalculator.calculateGameStatsEntry(
        cohortTippers: [tipper1, tipper2, tipper3],
        tipsForCohort: [tip1, tip2, null],
        league: League.nrl,
      );

      // 1 out of 3 tipped GameResult.a = 0.333
      expect(stats.percentageTippedHomeMargin, equals(0.333));
      // 1 out of 3 tipped GameResult.d = 0.333
      expect(stats.percentageTippedAway, equals(0.333));
      // 0 draw / other tips
      expect(stats.percentageTippedHome, equals(0.0));
      expect(stats.percentageTippedDraw, equals(0.0));
      expect(stats.percentageTippedAwayMargin, equals(0.0));

      // Points:
      // tip1: NRL Home margin (a) - correct! points: 4.
      // tip2: NRL Away (d) - incorrect! points: 0.
      // null: points: 0.
      // Total points = 4. Cohort length = 3.
      // Average points = 4 / 3 = 1.333.
      expect(stats.averagePoints, equals(1.333));
      // Non-null tip count = 2
      expect(stats.averagePointsTipCount, equals(2));
    });
  });
}
