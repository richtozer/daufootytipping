import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:dau_shared/services/fixture_import_applier.dart';
import 'package:dau_shared/services/kickoff_time.dart';

void main() {
  Map<String, dynamic> game({
    required int round,
    required int match,
    String league = 'nrl',
  }) => {
    'RoundNumber': round,
    'MatchNumber': match,
    'Location': 'X',
    'DateUtc': '2025-01-01T00:00:00Z',
  };

  test('buildGameUpdates creates dbkeys and attributes for both leagues', () {
    final applier = const FixtureImportApplier();
    final nrl = [game(round: 1, match: 2)];
    final afl = [game(round: 3, match: 4, league: 'afl')];

    final ops = applier.buildGameUpdates(nrl, afl);
    expect(ops.length, 2);
    expect(ops[0].dbkey, 'nrl-01-002');
    expect(ops[0].league, 'nrl');
    expect(ops[1].dbkey, 'afl-03-004');
    expect(ops[1].league, 'afl');
    expect(ops[0].attributes['RoundNumber'], 1);
    expect(ops[1].attributes['MatchNumber'], 4);
  });

  test('buildGameUpdates drops provider-only fields like Winner', () {
    final applier = const FixtureImportApplier();
    final nrl = <Map<String, dynamic>>[
      <String, dynamic>{
        ...game(round: 1, match: 2),
        'HomeTeam': 'Home',
        'AwayTeam': 'Away',
        'Group': 'A',
        'Winner': 'Home',
      },
    ];

    final ops = applier.buildGameUpdates(nrl, const []);

    expect(ops, hasLength(1));
    expect(ops.single.attributes.containsKey('Group'), isFalse);
    expect(ops.single.attributes.containsKey('Winner'), isFalse);
    expect(ops.single.attributes['HomeTeam'], 'Home');
  });

  test('tagGamesWithLeagueInPlace adds league key', () {
    final applier = const FixtureImportApplier();
    final arr = [game(round: 1, match: 1)];
    applier.tagGamesWithLeagueInPlace(arr, 'nrl');
    expect(arr.first['league'], 'nrl');
  });

  test('computeCombinedRoundsIfMissing returns null when rounds exist, list when empty', () {
    final applier = const FixtureImportApplier();
    final compWithRounds = DAUComp(
      dbkey: 'c1',
      name: 'Comp1',
      aflFixtureJsonURL: Uri.parse('https://afl'),
      nrlFixtureJsonURL: Uri.parse('https://nrl'),
      daurounds: const [],
    );

    // Initially empty -> should compute
    final computed = applier.computeCombinedRoundsIfMissing(compWithRounds, [
      game(round: 1, match: 1),
    ]);
    expect(computed, isNotNull);

    // With rounds -> should return null
    final comp2 = DAUComp(
      dbkey: 'c2',
      name: 'Comp2',
      aflFixtureJsonURL: Uri.parse('https://afl'),
      nrlFixtureJsonURL: Uri.parse('https://nrl'),
      daurounds: computed!,
    );
    final none = applier.computeCombinedRoundsIfMissing(comp2, [
      game(round: 2, match: 2),
    ]);
    expect(none, isNull);
  });

  group('kickoff freeze in buildGameUpdates', () {
    const applier = FixtureImportApplier();

    test('ignores kickoff change when game is officially scored (even <2h after kickoff)', () {
      final logs = <String>[];
      final existing = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{
          'DateUtc': '2026-06-01 10:00:00Z',
          'HomeTeamScore': 18,
          'AwayTeamScore': 12,
        },
      };
      final ops = applier.buildGameUpdates(
        [
          {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'Location': 'X',
            'DateUtc': '2026-06-02 10:00:00Z',
            'HomeTeamScore': 18,
            'AwayTeamScore': 12,
          },
        ],
        const [],
        existingGames: existing,
        now: DateTime.utc(2026, 6, 1, 11, 0), // 1h after kickoff (<2h)
        log: logs.add,
      );

      expect(ops.single.attributes[dateUtcKey], '2026-06-01 10:00:00Z');
      expect(
        ops.single.attributes[dateUtcEpochMsKey],
        kickoffEpochMsFromDateUtc('2026-06-01 10:00:00Z'),
      );
      expect(logs.single, contains('nrl-01-001'));
      expect(logs.single, contains('official score'));
    });

    test('ignores kickoff change once stored kickoff has passed, even into future or grace period', () {
      final logs = <String>[];
      final existing = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{'DateUtc': '2026-06-01 10:00:00Z'},
        'nrl-01-002': <String, dynamic>{'DateUtc': '2026-06-01 10:00:00Z'},
      };
      final ops = applier.buildGameUpdates(
        [
          {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'Location': 'X',
            // Inside 15m grace window from now (10:05) -> must stay frozen!
            'DateUtc': '2026-06-01 10:15:00Z',
          },
          {
            'RoundNumber': 1,
            'MatchNumber': 2,
            'Location': 'X',
            // Another past time -> also ignored once kickoff has passed.
            'DateUtc': '2026-06-01 09:30:00Z',
          },
        ],
        const [],
        existingGames: existing,
        now: DateTime.utc(2026, 6, 1, 10, 5),
        log: logs.add,
      );

      expect(ops[0].attributes[dateUtcKey], '2026-06-01 10:00:00Z');
      expect(
        ops[0].attributes[dateUtcEpochMsKey],
        kickoffEpochMsFromDateUtc('2026-06-01 10:00:00Z'),
      );
      expect(ops[1].attributes[dateUtcKey], '2026-06-01 10:00:00Z');
      expect(logs, hasLength(2));
    });

    test('freezes kickoff inside 15m grace window and accepts beyond it', () {
      final logs = <String>[];
      final existing = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{'DateUtc': '2026-06-01 10:00:00Z'},
      };

      final frozenOps = applier.buildGameUpdates(
        [
          {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'Location': 'X',
            'DateUtc': '2026-06-02 10:00:00Z',
          },
        ],
        const [],
        existingGames: existing,
        now: DateTime.utc(
          2026,
          6,
          1,
          9,
          45,
        ), // exactly 15m before stored kickoff
        log: logs.add,
      );
      expect(frozenOps.single.attributes[dateUtcKey], '2026-06-01 10:00:00Z');
      expect(logs.single, contains('grace window'));

      logs.clear();
      final acceptedOps = applier.buildGameUpdates(
        [
          {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'Location': 'X',
            'DateUtc': '2026-06-02 10:00:00Z',
          },
        ],
        const [],
        existingGames: existing,
        now: DateTime.utc(2026, 6, 1, 9, 44, 59),
        log: logs.add,
      );
      expect(acceptedOps.single.attributes[dateUtcKey], '2026-06-02 10:00:00Z');
      expect(logs, isEmpty);
    });

    test('accepts kickoff change for unstarted, unscored game', () {
      final logs = <String>[];
      final existing = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{'DateUtc': '2026-06-01 10:00:00Z'},
      };
      final ops = applier.buildGameUpdates(
        [
          {
            'RoundNumber': 1,
            'MatchNumber': 1,
            'Location': 'X',
            'DateUtc': '2026-06-02 10:00:00Z',
          },
        ],
        const [],
        existingGames: existing,
        now: DateTime.utc(2026, 6, 1, 9, 0),
        log: logs.add,
      );

      expect(ops.single.attributes[dateUtcKey], '2026-06-02 10:00:00Z');
      expect(
        ops.single.attributes[dateUtcEpochMsKey],
        kickoffEpochMsFromDateUtc('2026-06-02 10:00:00Z'),
      );
      expect(logs, isEmpty);
    });
  });

  group('recalculateRoundEndDates', () {
    const applier = FixtureImportApplier();

    test('computes maxKickoff + 3h, caps 1s before next start, handles empty and skips fully scored rounds', () {
      final rounds = [
        // Round 1: fully scored -> skipped even if end differs
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1, 5, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 1, 12, 0),
        ),
        // Round 2: close to Round 3 (<3h gap) -> capped at R3 start - 1s
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 2, 5, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 2, 12, 0),
        ),
        // Round 3: no games assigned -> end = start
        DAURound(
          dAUroundNumber: 3,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 3, 10, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 3, 20, 0),
        ),
        // Round 4: final round, postponed game extends end to kickoff + 3h
        DAURound(
          dAUroundNumber: 4,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 10, 5, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 10, 12, 0),
        ),
      ];

      final comp = DAUComp(
        dbkey: 'c1',
        name: 'Comp1',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: rounds,
      );

      final existingGames = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{
          'DateUtc': '2026-03-01 08:00:00Z',
          'HomeTeamScore': 20,
          'AwayTeamScore': 10,
        },
        'nrl-02-001': <String, dynamic>{
          'DateUtc': '2026-03-03 08:30:00Z', // +3h = 11:30 > R3 start 10:00
        },
        'afl-04-001': <String, dynamic>{'DateUtc': '2026-03-11 08:00:00Z'},
      };

      final changed = applier.recalculateRoundEndDates(
        comp: comp,
        gameUpdates: const [],
        existingGames: existingGames,
      );

      expect(changed.containsKey(0), isFalse); // fully scored round skipped
      expect(changed[1], '2026-03-03 09:59:59Z'); // R3 start (10:00:00) - 1s
      expect(changed[2], '2026-03-03 10:00:00Z'); // empty round -> end = start
      expect(changed[3], '2026-03-11 11:00:00Z'); // final round max + 3h

      // Re-running with same data yields no changed rounds.
      final secondRun = applier.recalculateRoundEndDates(
        comp: comp,
        gameUpdates: const [],
        existingGames: existingGames,
      );
      expect(secondRun, isEmpty);
    });

    test('caps fully scored round end at 1s before next round start when last unscored game moves out', () {
      final rounds = [
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1, 17, 0),
          // Previously included the 20:00 unscored game (+3h = 23:00).
          lastGameKickOffUTC: DateTime.utc(2026, 3, 1, 23, 0),
        ),
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 2, 10, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 2, 23, 0),
          // Admin moved Round 2 start back to 19:00, moving the 20:00 game out of Round 1.
          adminOverrideRoundStartDate: DateTime.utc(2026, 3, 1, 19, 0),
        ),
      ];
      final comp = DAUComp(
        dbkey: 'c1',
        name: 'Comp1',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: rounds,
      );

      final existingGames = <String, dynamic>{
        'nrl-01-001': <String, dynamic>{
          'DateUtc': '2026-03-01 18:00:00Z',
          'HomeTeamScore': 20,
          'AwayTeamScore': 10,
        },
        'nrl-01-002': <String, dynamic>{'DateUtc': '2026-03-01 20:00:00Z'},
      };

      final changed = applier.recalculateRoundEndDates(
        comp: comp,
        gameUpdates: const [],
        existingGames: existingGames,
      );

      expect(changed[0], '2026-03-01 18:59:59Z');
      expect(
        rounds[0].lastGameKickOffUTC,
        DateTime.utc(2026, 3, 1, 18, 59, 59),
      );
    });

    test(
      'keys returned changes by dAUroundNumber - 1 regardless of list order',
      () {
        final round2 = DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 8, 5, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 8, 12, 0),
        );
        final round1 = DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.utc(2026, 3, 1, 5, 0),
          lastGameKickOffUTC: DateTime.utc(2026, 3, 1, 12, 0),
        );
        final comp = DAUComp(
          dbkey: 'c1',
          name: 'Comp1',
          aflFixtureJsonURL: Uri.parse('https://afl'),
          nrlFixtureJsonURL: Uri.parse('https://nrl'),
          daurounds: [round2, round1],
        );

        final changed = applier.recalculateRoundEndDates(
          comp: comp,
          gameUpdates: const [],
          existingGames: <String, dynamic>{
            'nrl-01-001': <String, dynamic>{'DateUtc': '2026-03-01 10:00:00Z'},
            'nrl-02-001': <String, dynamic>{'DateUtc': '2026-03-08 10:00:00Z'},
          },
        );

        expect(changed.keys, containsAll([0, 1]));
        expect(changed[0], '2026-03-01 13:00:00Z');
        expect(changed[1], '2026-03-08 13:00:00Z');
      },
    );
  });
}
