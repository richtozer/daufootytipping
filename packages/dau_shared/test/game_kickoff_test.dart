import 'package:dau_shared/dau_shared.dart';
import 'package:test/test.dart';

void main() {
  Game gameAt(DateTime kickoff) {
    return Game(
      dbkey: 'nrl-01-001',
      league: League.nrl,
      homeTeam: Team(dbkey: 'nrl-Knights', name: 'Knights', league: League.nrl),
      awayTeam: Team(dbkey: 'nrl-Cowboys', name: 'Cowboys', league: League.nrl),
      location: 'Allegiant Stadium',
      startTimeUTC: kickoff,
      fixtureRoundNumber: 1,
      fixtureMatchNumber: 1,
    );
  }

  group('Game.toJson', () {
    test('writes DateUtc and the numeric kickoff together, and they agree', () {
      final json = gameAt(DateTime.utc(2026, 3, 1, 2, 15)).toJson();

      expect(json['DateUtc'], '2026-03-01 02:15:00Z');
      expect(json['DateUtcEpochMs'], 1772331300000);
      expect(
        kickoffEpochMsFromDateUtc(json['DateUtc'] as String),
        json['DateUtcEpochMs'],
      );
    });

    test('agrees with the instant of the model itself', () {
      final kickoff = DateTime.utc(2026, 10, 19, 16, 59, 58);

      expect(
        gameAt(kickoff).toJson()['DateUtcEpochMs'],
        kickoff.millisecondsSinceEpoch,
      );
    });

    test('is the same whichever zone the DateTime was built in', () {
      final utc = DateTime.utc(2026, 3, 1, 2, 15);
      final local = utc.toLocal();

      expect(gameAt(local).toJson()['DateUtc'], '2026-03-01 02:15:00Z');
      expect(
        gameAt(local).toJson()['DateUtcEpochMs'],
        gameAt(utc).toJson()['DateUtcEpochMs'],
      );
    });

    test('is read back by fromJson as the same instant', () {
      final json = gameAt(DateTime.utc(2026, 3, 1, 2, 15)).toJson();

      final back = Game.fromJson(
        'nrl-01-001',
        json,
        Team(dbkey: 'nrl-Knights', name: 'Knights', league: League.nrl),
        Team(dbkey: 'nrl-Cowboys', name: 'Cowboys', league: League.nrl),
      );

      expect(back.startTimeUTC, DateTime.utc(2026, 3, 1, 2, 15));
    });

    test('keeps every key it wrote before', () {
      final json = gameAt(DateTime.utc(2026, 3, 1, 2, 15)).toJson();

      expect(
        json.keys,
        containsAll(<String>[
          'League',
          'HomeTeam',
          'AwayTeam',
          'Location',
          'DateUtc',
          'RoundNumber',
          'MatchNumber',
          'HomeTeamScore',
          'AwayTeamScore',
        ]),
      );
    });
  });
}
