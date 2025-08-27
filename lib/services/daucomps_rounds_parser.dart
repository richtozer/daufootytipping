import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';

class DaucompsRoundsParser {
  const DaucompsRoundsParser();

  List<DAURound> parseRounds(dynamic daucompAsJSON, {String combinedRoundsPath = 'combinedRounds2'}) {
    final daurounds = <DAURound>[];
    if (daucompAsJSON[combinedRoundsPath] != null) {
      final combinedRounds = daucompAsJSON[combinedRoundsPath] as List<dynamic>;
      for (var i = 0; i < combinedRounds.length; i++) {
        daurounds.add(
          DAURound.fromJson(
            Map<String, dynamic>.from(combinedRounds[i] as Map),
            i + 1,
          ),
        );
      }
    }
    return daurounds;
  }

  DateTime? computeGreaterEndDate(DAUComp comp) {
    if (comp.aflRegularCompEndDateUTC != null || comp.nrlRegularCompEndDateUTC != null) {
      if (comp.aflRegularCompEndDateUTC == null) return comp.nrlRegularCompEndDateUTC;
      if (comp.nrlRegularCompEndDateUTC == null) return comp.aflRegularCompEndDateUTC;
      return comp.aflRegularCompEndDateUTC!.isAfter(comp.nrlRegularCompEndDateUTC!)
          ? comp.aflRegularCompEndDateUTC!
          : comp.nrlRegularCompEndDateUTC!;
    }
    return null;
  }

  void applyCutoffFilter(DAUComp comp) {
    final greaterEndDate = computeGreaterEndDate(comp);
    if (greaterEndDate == null) return;
    comp.daurounds.removeWhere((round) => round.getRoundStartDate().isAfter(greaterEndDate));
  }
}

