import 'package:daufootytipping/models/crowdsourcedscore.dart';
import 'package:firebase_database/firebase_database.dart';

/// What a client writes to record a live score: one entry under the game's
/// `history`, in the only shape the database rules accept from a client.
///
/// Exactly these four fields and nothing else. `t` is the database's own clock
/// (the rules require `t` to equal the server's `now`), never the device's, so
/// no one can back-date or post-date a score; the entry's score, team and tipper
/// are all the rules let a client choose. The running score for the game
/// (`current`) is built from these entries by the server, and a client cannot
/// write it.
Map<String, Object?> liveScoreHistoryEntry(CrowdSourcedScore score) =>
    <String, Object?>{
      'tipperID': score.tipperID,
      'scoreTeam': score.scoreTeam.name,
      'interimScore': score.interimScore,
      't': ServerValue.timestamp,
    };

/// The key of [score]'s entry under the game's `history`. It only has to be
/// unique: entries are create-only, and the server orders them by `t`, not by
/// the key. The device's clock makes it unique, as it did before.
String liveScoreHistoryKey(CrowdSourcedScore score) =>
    '${score.submittedTimeUTC.microsecondsSinceEpoch}-${score.scoreTeam.name}';
