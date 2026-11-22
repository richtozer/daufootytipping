import '../models/game.dart';

/// The keys of the teams that play in more than one round of [games], which
/// should all come from one comp.
///
/// A fixture lists its finals before anyone has qualified, with placeholder
/// teams such as "1st" or "Winner of QF1" that each play one week. Every club
/// plays many rounds, so counting rounds tells the two apart.
Set<String> teamKeysInSeveralRounds(Iterable<Game> games) {
  final roundsByTeam = <String, Set<int>>{};
  for (final game in games) {
    for (final team in [game.homeTeam, game.awayTeam]) {
      (roundsByTeam[team.dbkey] ??= {}).add(game.fixtureRoundNumber);
    }
  }
  return {
    for (final MapEntry(key: teamKey, value: rounds) in roundsByTeam.entries)
      if (rounds.length > 1) teamKey,
  };
}
