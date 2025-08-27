import 'package:intl/intl.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';

class CombinedRoundsPersistence {
  const CombinedRoundsPersistence();

  Map<String, dynamic> buildCombinedRoundsUpdates(
    DAUComp comp,
    List<DAURound> combinedRounds, {
    String daucompsPath = '/AllDAUComps',
    String combinedRoundsPath = 'combinedRounds2',
  }) {
    final updates = <String, dynamic>{};
    for (var i = 0; i < combinedRounds.length; i++) {
      updates['$daucompsPath/${comp.dbkey}/$combinedRoundsPath/$i/roundStartDate'] =
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(combinedRounds[i].firstGameKickOffUTC)}Z';
      updates['$daucompsPath/${comp.dbkey}/$combinedRoundsPath/$i/roundEndDate'] =
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

