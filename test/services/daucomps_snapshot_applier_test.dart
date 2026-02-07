import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/daucomps_snapshot_applier.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

void main() {
  Map<String, dynamic> compJson({
    required String name,
    required String aflUrl,
    required String nrlUrl,
    String? endAfl,
    String? endNrl,
    required List<Map<String, String>> rounds,
  }) {
    final m = <String, dynamic>{
      p.compNameKey: name,
      p.aflFixtureJsonURLKey: aflUrl,
      p.nrlFixtureJsonURLKey: nrlUrl,
      p.combinedRoundsPath: rounds,
    };
    if (endAfl != null) m[p.aflRegularCompEndDateUTCKey] = endAfl;
    if (endNrl != null) m[p.nrlRegularCompEndDateUTCKey] = endNrl;
    return m;
  }

  Map<String, String> round(String start, String end) => {
        p.roundStartDateKey: start,
        p.roundEndDateKey: end,
      };

  test('adds, updates, removes comps and marks relink when rounds change', () {
    final applier = const DauCompsSnapshotApplier();

    final existing = <DAUComp>[
      DAUComp(
        dbkey: 'a',
        name: 'Comp A',
        aflFixtureJsonURL: Uri.parse('https://afl-a'),
        nrlFixtureJsonURL: Uri.parse('https://nrl-a'),
        daurounds: [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
            lastGameKickOffUTC: DateTime.parse('2025-01-02T00:00:00Z'),
          )
        ],
      ),
      DAUComp(
        dbkey: 'b',
        name: 'Comp B',
        aflFixtureJsonURL: Uri.parse('https://afl-b'),
        nrlFixtureJsonURL: Uri.parse('https://nrl-b'),
        daurounds: const [],
      ),
    ];

    final db = <String, dynamic>{
      'a': compJson(
        name: 'Comp A',
        aflUrl: 'https://afl-a',
        nrlUrl: 'https://nrl-a',
        rounds: [
          round('2025-01-01T00:00:00Z', '2025-01-02T00:00:00Z'),
          // add new second round
          round('2025-01-08T00:00:00Z', '2025-01-09T00:00:00Z'),
        ],
      ),
      // b removed from DB
      // c added as new comp
      'c': compJson(
        name: 'Comp C',
        aflUrl: 'https://afl-c',
        nrlUrl: 'https://nrl-c',
        rounds: [round('2025-02-01T00:00:00Z', '2025-02-02T00:00:00Z')],
      ),
    };

    final res = applier.apply(databaseValue: db, currentComps: existing);

    // b removed, c added, a retained
    expect(res.comps.map((c) => c.dbkey), containsAll(['a', 'c']));
    expect(res.comps.map((c) => c.dbkey), isNot(contains('b')));

    final compA = res.comps.firstWhere((c) => c.dbkey == 'a');
    expect(compA.daurounds.length, 2); // round added
    expect(res.compKeysNeedingRelink.contains('a'), isTrue);
  });

  test('replacement on final field change triggers relink', () {
    final applier = const DauCompsSnapshotApplier();
    final existing = <DAUComp>[
      DAUComp(
        dbkey: 'x',
        name: 'Old Name',
        aflFixtureJsonURL: Uri.parse('https://afl-x'),
        nrlFixtureJsonURL: Uri.parse('https://nrl-x'),
        daurounds: const [],
      ),
    ];
    final db = {
      'x': compJson(
        name: 'New Name',
        aflUrl: 'https://afl-x',
        nrlUrl: 'https://nrl-x',
        rounds: const [],
      ),
    };
    final res = applier.apply(databaseValue: db, currentComps: existing);
    expect(res.compKeysNeedingRelink.contains('x'), isTrue);
    expect(res.comps.firstWhere((c) => c.dbkey == 'x').name, 'New Name');
  });

  test('applies cutoff filter to remove late rounds', () {
    final applier = const DauCompsSnapshotApplier();
    final existing = <DAUComp>[];
    final db = {
      'k': compJson(
        name: 'K',
        aflUrl: 'https://afl-k',
        nrlUrl: 'https://nrl-k',
        endAfl: '2025-01-09T00:00:00Z',
        rounds: [
          round('2025-01-01T00:00:00Z', '2025-01-02T00:00:00Z'),
          // after cutoff
          round('2025-02-01T00:00:00Z', '2025-02-02T00:00:00Z'),
        ],
      ),
    };

    final res = applier.apply(databaseValue: db, currentComps: existing);
    final compK = res.comps.firstWhere((c) => c.dbkey == 'k');
    expect(compK.daurounds.length, 1);
  });
}

