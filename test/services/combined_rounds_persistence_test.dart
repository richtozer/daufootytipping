import 'package:test/test.dart';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/combined_rounds_persistence.dart';

void main() {
  group('CombinedRoundsPersistence', () {
    final p = CombinedRoundsPersistence();

    test('buildCombinedRoundsUpdates creates start/end updates and removals', () {
      final comp = DAUComp(
        dbkey: 'comp123',
        name: 'C',
        aflFixtureJsonURL: Uri.parse('https://afl'),
        nrlFixtureJsonURL: Uri.parse('https://nrl'),
        daurounds: [
          DAURound(
            dAUroundNumber: 1,
            firstGameKickOffUTC: DateTime.parse('2025-01-01T00:00:00Z'),
            lastGameKickOffUTC: DateTime.parse('2025-01-01T12:00:00Z'),
          ),
          DAURound(
            dAUroundNumber: 2,
            firstGameKickOffUTC: DateTime.parse('2025-01-08T00:00:00Z'),
            lastGameKickOffUTC: DateTime.parse('2025-01-08T12:00:00Z'),
          ),
          DAURound(
            dAUroundNumber: 3,
            firstGameKickOffUTC: DateTime.parse('2025-01-15T00:00:00Z'),
            lastGameKickOffUTC: DateTime.parse('2025-01-15T12:00:00Z'),
          ),
        ],
      );
      final combined = <DAURound>[
        DAURound(
          dAUroundNumber: 1,
          firstGameKickOffUTC: DateTime.parse('2025-01-01T03:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-01-01T13:00:00Z'),
        ),
        DAURound(
          dAUroundNumber: 2,
          firstGameKickOffUTC: DateTime.parse('2025-01-08T03:00:00Z'),
          lastGameKickOffUTC: DateTime.parse('2025-01-08T13:00:00Z'),
        ),
      ];

      final updates = p.buildCombinedRoundsUpdates(comp, combined,
          daucompsPath: '/AllDAUComps', combinedRoundsPath: 'combinedRounds2');

      expect(
        updates.containsKey('/AllDAUComps/comp123/combinedRounds2/0/roundStartDate'),
        isTrue,
      );
      expect(
        updates.containsKey('/AllDAUComps/comp123/combinedRounds2/0/roundEndDate'),
        isTrue,
      );

      // Expect removal for index 2
      expect(updates['/AllDAUComps/comp123/combinedRounds2/2'], isNull);
    });
  });
}

