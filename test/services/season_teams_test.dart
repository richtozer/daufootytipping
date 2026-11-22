import 'package:dau_shared/services/season_teams.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:test/test.dart';

void main() {
  Team team(String key) => Team(dbkey: key, name: key, league: League.afl);
  Game game(int round, String home, String away) => Game(
    dbkey: 'afl-$round-$home',
    league: League.afl,
    homeTeam: team(home),
    awayTeam: team(away),
    location: 'Ground',
    startTimeUTC: DateTime.utc(2027, 3, round),
    fixtureRoundNumber: round,
    fixtureMatchNumber: 1,
  );

  test('a team that plays in two or more rounds is a season team; a finals '
      'placeholder, which plays in one, is not', () {
    final keys = teamKeysInSeveralRounds([
      game(1, 'afl-Crows', 'afl-Swans'),
      game(2, 'afl-Swans', 'afl-Crows'),
      game(26, 'afl-1st', 'afl-4th'),
    ]);

    expect(keys, {'afl-Crows', 'afl-Swans'});
  });

  test('no games, no season teams', () {
    expect(teamKeysInSeveralRounds(const []), isEmpty);
  });
}
