import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:daufootytipping/services/combined_rounds_persistence.dart';
import 'package:intl/intl.dart';

void main() {
  group('CombinedRoundsPersistence.buildCombinedRoundsUpdates', () {
    DAURound round(int n, String startZ, String endZ) => DAURound(
          dAUroundNumber: n,
          firstGameKickOffUTC: DateTime.parse(startZ),
          lastGameKickOffUTC: DateTime.parse(endZ),
        );

    test('writes start/end for new rounds and nulls extra existing rounds', () {
      final comp = DAUComp(
        dbkey: 'comp1',
        name: 'Comp',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [
          round(1, '2025-01-01T00:00:00Z', '2025-01-02T00:00:00Z'),
          round(2, '2025-01-08T00:00:00Z', '2025-01-09T00:00:00Z'),
          // existing third round to be removed
          round(3, '2025-01-15T00:00:00Z', '2025-01-16T00:00:00Z'),
        ],
      );

      final combined = [
        round(1, '2025-01-01T00:00:00Z', '2025-01-02T00:00:00Z'),
        round(2, '2025-01-08T00:00:00Z', '2025-01-09T00:00:00Z'),
      ];

      final svc = const CombinedRoundsPersistence();
      final updates = svc.buildCombinedRoundsUpdates(comp, combined);

      // Verify written start/end are in expected paths with expected formatting
      final base = '${p.daucompsPath}/${comp.dbkey}/${p.combinedRoundsPath}';
      // The service formats using local time + 'Z' suffix; mirror that here
      String fmt(String z) => '${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(z))}Z';
      expect(updates['$base/0/${p.roundStartDateKey}'], fmt('2025-01-01T00:00:00Z'));
      expect(updates['$base/0/${p.roundEndDateKey}'], fmt('2025-01-02T00:00:00Z'));
      expect(updates['$base/1/${p.roundStartDateKey}'], fmt('2025-01-08T00:00:00Z'));
      expect(updates['$base/1/${p.roundEndDateKey}'], fmt('2025-01-09T00:00:00Z'));

      // Existing extra round index should be nulled out
      expect(updates['$base/2'], isNull);
    });
  });
}
