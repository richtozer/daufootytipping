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
        OutstandingTipsCalculator.appBadgeRoundForTime(
          rounds: <DAURound>[round],
          now: now.subtract(const Duration(microseconds: 1)),
        ),
        isNull,
      );
      expect(
        OutstandingTipsCalculator.appBadgeRoundForTime(
          rounds: <DAURound>[round],
          now: now,
        ),
        same(round),
      );
    });

    test('deactivates a round after its last kickoff', () {
      final round = DAURound(
        dAUroundNumber: 1,
        firstGameKickOffUTC: now.subtract(const Duration(days: 2)),
        lastGameKickOffUTC: now,
      );

      expect(
        OutstandingTipsCalculator.appBadgeRoundForTime(
          rounds: <DAURound>[round],
          now: now,
        ),
        same(round),
      );
      expect(
        OutstandingTipsCalculator.appBadgeRoundForTime(
          rounds: <DAURound>[round],
          now: now.add(const Duration(microseconds: 1)),
        ),
        isNull,
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
