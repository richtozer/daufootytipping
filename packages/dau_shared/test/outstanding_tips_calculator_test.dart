import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  group('OutstandingTipsCalculator', () {
    final now = DateTime.utc(2026, 8, 4, 12);

    test('counts untipped not-started and starting-soon games', () {
      final games = <Game>[
        _game('later', now.add(const Duration(days: 2))),
        _game('soon', now.add(const Duration(hours: 2))),
        _game('started', now.subtract(const Duration(minutes: 1))),
      ];

      final count = OutstandingTipsCalculator.countUpcomingUntippedGames(
        games: games,
        submittedGameKeys: const <String>{},
        now: now,
      );

      expect(count, 2);
    });

    test('does not count submitted upcoming games', () {
      final games = <Game>[
        _game('submitted', now.add(const Duration(hours: 2))),
        _game('missing', now.add(const Duration(hours: 3))),
      ];

      final count = OutstandingTipsCalculator.countUpcomingUntippedGames(
        games: games,
        submittedGameKeys: const <String>{'submitted'},
        now: now,
      );

      expect(count, 1);
    });

    test('returns zero for a fully tipped set of games', () {
      final games = <Game>[
        _game('one', now.add(const Duration(hours: 2))),
        _game('two', now.add(const Duration(hours: 3))),
      ];

      final count = OutstandingTipsCalculator.countUpcomingUntippedGames(
        games: games,
        submittedGameKeys: const <String>{'one', 'two'},
        now: now,
      );

      expect(count, 0);
    });

    test('activates a round exactly 48 hours before its first kickoff', () {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.add(const Duration(hours: 48)),
        lastGameKickOffUTC: now.add(const Duration(days: 3)),
      );

      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round],
          now: now.subtract(const Duration(microseconds: 1)),
        ),
        isEmpty,
      );
      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round],
          now: now,
        ),
        <DAURound>[round],
      );
    });

    test('deactivates a round after its last kickoff', () {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 2)),
        lastGameKickOffUTC: now,
      );

      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round],
          now: now,
        ),
        <DAURound>[round],
      );
      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round],
          now: now.add(const Duration(microseconds: 1)),
        ),
        isEmpty,
      );
    });

    test('uses the admin override start for badge activation', () {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.add(const Duration(hours: 72)),
        lastGameKickOffUTC: now.add(const Duration(days: 4)),
        adminOverrideRoundStartDate: now.add(const Duration(hours: 48)),
      );

      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round],
          now: now,
        ),
        <DAURound>[round],
      );
    });

    test('skips an empty round whose end is at or before its start', () {
      final emptyRound = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.add(const Duration(hours: 24)),
        lastGameKickOffUTC: now.add(const Duration(hours: 24)),
      );

      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[emptyRound],
          now: now,
        ),
        isEmpty,
      );
    });

    test('returns all overlapping active rounds', () {
      final round1 = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 3)),
        lastGameKickOffUTC: now.add(const Duration(hours: 6)),
      );
      final round2 = DAURound(
        dAUroundNumber: 2,
        firstGameKickOffUTC: now.add(const Duration(hours: 40)),
        lastGameKickOffUTC: now.add(const Duration(days: 4)),
      );
      expect(
        OutstandingTipsCalculator.appBadgeRoundsForTime(
          rounds: <DAURound>[round1, round2],
          now: now,
        ),
        <DAURound>[round1, round2],
      );
    });
  });
}

Game _game(String dbkey, DateTime startTimeUTC) {
  return Game(
    dbkey: dbkey,
    league: League.nrl,
    homeTeam: Team(dbkey: 'NRL-home', name: 'Home', league: League.nrl),
    awayTeam: Team(dbkey: 'NRL-away', name: 'Away', league: League.nrl),
    location: 'Stadium',
    startTimeUTC: startTimeUTC,
    fixtureRoundNumber: 1,
    fixtureMatchNumber: 1,
  );
}
