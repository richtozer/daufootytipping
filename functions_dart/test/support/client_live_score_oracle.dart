import 'package:dau_shared/dau_shared.dart';

/// What the 1.4.x client does with live scores, ported line for line from
/// `StatsViewModel` (`_addMultipleLiveScores` and `_liveScoreCurrentPayload`,
/// lib/view_models/stats_viewmodel.dart), so the server's calculation can be held
/// to it. Where the client's code is quirky the quirk is kept: this is the
/// reference, not an improvement on it.
///
/// It plays one client's view of one game: a local list of crowd-sourced scores
/// that each submission appends to and trims, and the two writes the client then
/// makes (the whole `current` snapshot, and a `history` entry per score).
class ClientLiveScoreOracle {
  /// The game's local list, as the client holds it.
  List<CrowdSourcedScore> scores = <CrowdSourcedScore>[];

  /// The `history` node the client's writes have built up.
  final Map<String, Object?> history = <String, Object?>{};

  /// The `current` snapshot the client last wrote.
  Map<String, Object?>? current;

  /// One submission: the scores the tipper changed, added together.
  void submit(List<CrowdSourcedScore> toAdd) {
    if (toAdd.isEmpty) {
      return;
    }
    scores = <CrowdSourcedScore>[...scores, ...toAdd];

    // "Clean up old scores for each team that was updated": more than three for
    // a team, and the earliest goes.
    for (final scoreTeam in <ScoringTeam>{ScoringTeam.home, ScoringTeam.away}) {
      if (!toAdd.any((score) => score.scoreTeam == scoreTeam)) {
        continue;
      }
      final forTeam = scores.where((e) => e.scoreTeam == scoreTeam);
      if (forTeam.length > 3) {
        final earliest = forTeam
            .reduce(
              (value, element) =>
                  value.submittedTimeUTC.isBefore(element.submittedTimeUTC)
                  ? value
                  : element,
            )
            .submittedTimeUTC;
        scores.removeWhere(
          (e) => e.scoreTeam == scoreTeam && e.submittedTimeUTC == earliest,
        );
      }
    }

    // `_writeLiveScoreToDb`: the snapshot, and a history entry per submitted score.
    current = _payload();
    for (final score in toAdd) {
      history['${score.submittedTimeUTC.microsecondsSinceEpoch}-${score.scoreTeam.name}'] =
          score.toJson();
    }
  }

  Map<String, Object?> _payload() {
    final scoring = Scoring(crowdSourcedScores: scores);
    CrowdSourcedScore? latestScore;
    for (final score in scores) {
      if (latestScore == null ||
          score.submittedTimeUTC.isAfter(latestScore.submittedTimeUTC)) {
        latestScore = score;
      }
    }
    return <String, Object?>{
      'homeInterimScore': scoring.currentScore(ScoringTeam.home),
      'awayInterimScore': scoring.currentScore(ScoringTeam.away),
      'submittedTimeUTC': latestScore?.submittedTimeUTC.toIso8601String(),
      'tipperID': latestScore?.tipperID,
      'gameComplete': latestScore?.gameComplete ?? false,
      'crowdSourcedScores': scores.map((score) => score.toJson()).toList(),
    };
  }
}
