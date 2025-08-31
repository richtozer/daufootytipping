import 'package:intl/intl.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class CombinedRoundsPersistence {
  const CombinedRoundsPersistence();

  Map<String, dynamic> buildCombinedRoundsUpdates(
    DAUComp comp,
    List<DAURound> combinedRounds, {
    String daucompsPath = p.daucompsPath,
    String combinedRoundsPath = p.combinedRoundsPath,
  }) {
    final updates = <String, dynamic>{};
    for (var i = 0; i < combinedRounds.length; i++) {
      updates['$daucompsPath/${comp.dbkey}/$combinedRoundsPath/$i/${p.roundStartDateKey}'] =
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].firstGameKickOffUTC)}Z';
      updates['$daucompsPath/${comp.dbkey}/$combinedRoundsPath/$i/${p.roundEndDateKey}'] =
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].lastGameKickOffUTC)}Z';
    }

    // Remove extra rounds if existing exceeds new combined length
    if (comp.daurounds.length > combinedRounds.length) {
      for (var i = combinedRounds.length; i < comp.daurounds.length; i++) {
        updates['$daucompsPath/${comp.dbkey}/$combinedRoundsPath/$i'] = null;
      }
    }

    return updates;
  }
}
