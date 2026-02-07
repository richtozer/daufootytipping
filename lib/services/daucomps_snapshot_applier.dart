import 'dart:collection';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/services/daucomps_rounds_parser.dart';
import 'package:daufootytipping/constants/paths.dart' as p;

class DauCompsApplyResult {
  final List<DAUComp> comps;
  final Set<String> compKeysNeedingRelink; // replacement or rounds changed

  const DauCompsApplyResult({required this.comps, required this.compKeysNeedingRelink});
}

class DauCompsSnapshotApplier {
  final DaucompsRoundsParser _parser;

  const DauCompsSnapshotApplier({DaucompsRoundsParser parser = const DaucompsRoundsParser()})
      : _parser = parser;

  DauCompsApplyResult apply({
    required Map<String, dynamic>? databaseValue,
    required List<DAUComp> currentComps,
    String combinedRoundsPath = p.combinedRoundsPath,
  }) {
    if (databaseValue == null || databaseValue.isEmpty) {
      return const DauCompsApplyResult(comps: <DAUComp>[], compKeysNeedingRelink: <String>{});
    }

    final existing = LinkedHashMap<String, DAUComp>.fromEntries(
      currentComps.where((c) => c.dbkey != null).map((c) => MapEntry(c.dbkey!, c)),
    );
    final processed = <String>{};
    final relink = <String>{};

    for (final entry in databaseValue.entries) {
      final dbKey = entry.key;
      final json = entry.value;
      processed.add(dbKey);

      // Build comparison object from DB
      final dbRounds = _parser.parseRounds(json, combinedRoundsPath: combinedRoundsPath);
      final dbComp = DAUComp.fromJson(Map<String, dynamic>.from(json as Map), dbKey, dbRounds);
      _parser.applyCutoffFilter(dbComp);

      if (existing.containsKey(dbKey)) {
        final existingComp = existing[dbKey]!;
        final finalChanged = _finalFieldsChanged(existingComp, dbComp);
        if (finalChanged) {
          existing[dbKey] = dbComp;
          relink.add(dbKey);
          continue;
        }

        final roundsChanged = _updateMutableAndRounds(existingComp, dbComp);
        if (roundsChanged) relink.add(dbKey);
      } else {
        existing[dbKey] = dbComp;
      }
    }

    // Remove comps not present in DB
    final toRemove = existing.keys.where((k) => !processed.contains(k)).toList();
    for (final k in toRemove) {
      existing.remove(k);
    }

    return DauCompsApplyResult(comps: existing.values.toList(), compKeysNeedingRelink: relink);
  }

  bool _finalFieldsChanged(DAUComp a, DAUComp b) {
    return a.name != b.name || a.aflFixtureJsonURL != b.aflFixtureJsonURL || a.nrlFixtureJsonURL != b.nrlFixtureJsonURL;
  }

  bool _updateMutableAndRounds(DAUComp target, DAUComp source) {
    bool changed = false;
    if (target.aflRegularCompEndDateUTC != source.aflRegularCompEndDateUTC) {
      target.aflRegularCompEndDateUTC = source.aflRegularCompEndDateUTC;
      changed = true;
    }
    if (target.nrlRegularCompEndDateUTC != source.nrlRegularCompEndDateUTC) {
      target.nrlRegularCompEndDateUTC = source.nrlRegularCompEndDateUTC;
      changed = true;
    }
    if (target.lastFixtureUpdateTimestampUTC != source.lastFixtureUpdateTimestampUTC) {
      target.lastFixtureUpdateTimestampUTC = source.lastFixtureUpdateTimestampUTC;
      changed = true;
    }

    final roundsChanged = _updateRounds(target, source.daurounds);
    return changed || roundsChanged;
  }

  bool _updateRounds(DAUComp existingComp, List<DAURound> databaseRounds) {
    bool roundsChanged = false;
    final existingRoundsMap = {for (final r in existingComp.daurounds) r.dAUroundNumber: r};
    final databaseRoundsMap = {for (final r in databaseRounds) r.dAUroundNumber: r};

    for (final dbRound in databaseRounds) {
      final n = dbRound.dAUroundNumber;
      if (existingRoundsMap.containsKey(n)) {
        if (_updateSingleRound(existingRoundsMap[n]!, dbRound)) {
          roundsChanged = true;
        }
      } else {
        existingComp.daurounds.add(dbRound);
        roundsChanged = true;
      }
    }

    final toRemove = existingComp.daurounds.where((r) => !databaseRoundsMap.containsKey(r.dAUroundNumber)).toList();
    for (final r in toRemove) {
      existingComp.daurounds.remove(r);
      roundsChanged = true;
    }

    if (roundsChanged) {
      existingComp.daurounds.sort((a, b) => a.dAUroundNumber.compareTo(b.dAUroundNumber));
    }
    return roundsChanged;
  }

  bool _updateSingleRound(DAURound existingRound, DAURound databaseRound) {
    bool changed = false;
    if (existingRound.firstGameKickOffUTC != databaseRound.firstGameKickOffUTC) {
      existingRound.firstGameKickOffUTC = databaseRound.firstGameKickOffUTC;
      changed = true;
    }
    if (existingRound.lastGameKickOffUTC != databaseRound.lastGameKickOffUTC) {
      existingRound.lastGameKickOffUTC = databaseRound.lastGameKickOffUTC;
      changed = true;
    }
    if (existingRound.adminOverrideRoundStartDate != databaseRound.adminOverrideRoundStartDate) {
      existingRound.adminOverrideRoundStartDate = databaseRound.adminOverrideRoundStartDate;
      changed = true;
    }
    if (existingRound.adminOverrideRoundEndDate != databaseRound.adminOverrideRoundEndDate) {
      existingRound.adminOverrideRoundEndDate = databaseRound.adminOverrideRoundEndDate;
      changed = true;
    }
    return changed;
  }
}

