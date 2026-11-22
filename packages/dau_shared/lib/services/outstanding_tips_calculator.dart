import '../models/dauround.dart';
import '../models/game.dart';

class OutstandingTipsCalculator {
  const OutstandingTipsCalculator._();

  static const Duration appBadgeActivationLeadTime = Duration(hours: 48);

  static List<DAURound> appBadgeRoundsForTime({
    required Iterable<DAURound> rounds,
    required DateTime now,
  }) {
    final activeRounds = <DAURound>[];
    for (final round in rounds) {
      final roundStart = round.getRoundStartDate();
      // Empty rounds (end <= start) must not open a 48h badge window.
      if (!round.lastGameKickOffUTC.isAfter(roundStart)) {
        continue;
      }
      final activationTime = roundStart.subtract(appBadgeActivationLeadTime);
      final isActivated = !now.isBefore(activationTime);
      final hasNotPassedLastKickoff = !now.isAfter(round.lastGameKickOffUTC);
      if (isActivated && hasNotPassedLastKickoff) {
        activeRounds.add(round);
      }
    }
    return activeRounds;
  }

  static int countUpcomingUntippedGames({
    required Iterable<Game> games,
    required Set<String> submittedGameKeys,
    required DateTime now,
  }) {
    var outstanding = 0;
    for (final game in games) {
      final gameState = game.getGameState(now);
      final isUpcoming =
          gameState == GameState.notStarted ||
          gameState == GameState.startingSoon;
      if (isUpcoming && !submittedGameKeys.contains(game.dbkey)) {
        outstanding++;
      }
    }
    return outstanding;
  }
}
