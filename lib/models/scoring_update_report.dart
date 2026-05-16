class ScoringStateSnapshot {
  final Map<String, ScoringRoundSnapshot> roundEntries;
  final Map<String, ScoringLeaderboardSnapshot> leaderboardEntries;

  const ScoringStateSnapshot({
    required this.roundEntries,
    required this.leaderboardEntries,
  });
}

class ScoringRoundSnapshot {
  final String? tipperDbKey;
  final String tipperName;
  final int roundNumber;
  final int total;
  final int nrl;
  final int afl;
  final int rank;

  const ScoringRoundSnapshot({
    required this.tipperDbKey,
    required this.tipperName,
    required this.roundNumber,
    required this.total,
    required this.nrl,
    required this.afl,
    required this.rank,
  });

  String get key => '$roundNumber:${tipperDbKey ?? tipperName}';
}

class ScoringLeaderboardSnapshot {
  final String? tipperDbKey;
  final String tipperName;
  final int rank;
  final int total;
  final int nrl;
  final int afl;
  final int roundsWon;
  final int margins;
  final int ups;

  const ScoringLeaderboardSnapshot({
    required this.tipperDbKey,
    required this.tipperName,
    required this.rank,
    required this.total,
    required this.nrl,
    required this.afl,
    required this.roundsWon,
    required this.margins,
    required this.ups,
  });

  String get key => tipperDbKey ?? tipperName;
}

class ScoringRoundChange {
  final String? tipperDbKey;
  final String tipperName;
  final int roundNumber;
  final int beforeTotal;
  final int afterTotal;
  final int beforeNrl;
  final int afterNrl;
  final int beforeAfl;
  final int afterAfl;
  final int beforeRank;
  final int afterRank;

  const ScoringRoundChange({
    required this.tipperDbKey,
    required this.tipperName,
    required this.roundNumber,
    required this.beforeTotal,
    required this.afterTotal,
    required this.beforeNrl,
    required this.afterNrl,
    required this.beforeAfl,
    required this.afterAfl,
    required this.beforeRank,
    required this.afterRank,
  });

  int get totalDelta => afterTotal - beforeTotal;
  int get rankDelta => beforeRank - afterRank;
  bool get hasChange =>
      beforeTotal != afterTotal ||
      beforeNrl != afterNrl ||
      beforeAfl != afterAfl ||
      beforeRank != afterRank;
}

class ScoringLeaderboardChange {
  final String? tipperDbKey;
  final String tipperName;
  final int beforeRank;
  final int afterRank;
  final int beforeTotal;
  final int afterTotal;
  final int beforeNrl;
  final int afterNrl;
  final int beforeAfl;
  final int afterAfl;
  final int beforeRoundsWon;
  final int afterRoundsWon;
  final int beforeMargins;
  final int afterMargins;
  final int beforeUps;
  final int afterUps;

  const ScoringLeaderboardChange({
    required this.tipperDbKey,
    required this.tipperName,
    required this.beforeRank,
    required this.afterRank,
    required this.beforeTotal,
    required this.afterTotal,
    required this.beforeNrl,
    required this.afterNrl,
    required this.beforeAfl,
    required this.afterAfl,
    required this.beforeRoundsWon,
    required this.afterRoundsWon,
    required this.beforeMargins,
    required this.afterMargins,
    required this.beforeUps,
    required this.afterUps,
  });

  int get totalDelta => afterTotal - beforeTotal;
  int get rankDelta => beforeRank - afterRank;
  bool get hasChange =>
      beforeRank != afterRank ||
      beforeTotal != afterTotal ||
      beforeNrl != afterNrl ||
      beforeAfl != afterAfl ||
      beforeRoundsWon != afterRoundsWon ||
      beforeMargins != afterMargins ||
      beforeUps != afterUps;
}

class ScoringGameStatsChange {
  final String gameDbKey;
  final String gameName;
  final bool isPaidCohort;
  final double? beforeAveragePoints;
  final double? afterAveragePoints;
  final int? beforeTipCount;
  final int? afterTipCount;

  const ScoringGameStatsChange({
    required this.gameDbKey,
    required this.gameName,
    required this.isPaidCohort,
    required this.beforeAveragePoints,
    required this.afterAveragePoints,
    required this.beforeTipCount,
    required this.afterTipCount,
  });

  String get cohortLabel => isPaidCohort ? 'Paid' : 'Free';

  bool get hasChange =>
      beforeAveragePoints != null && beforeAveragePoints != afterAveragePoints;
}

class ScoringUpdateReport {
  final String resultMessage;
  final List<ScoringLeaderboardChange> leaderboardChanges;
  final List<ScoringRoundChange> roundChanges;
  final List<ScoringGameStatsChange> gameStatsChanges;

  const ScoringUpdateReport({
    required this.resultMessage,
    required this.leaderboardChanges,
    required this.roundChanges,
    this.gameStatsChanges = const <ScoringGameStatsChange>[],
  });

  bool get hasChanges =>
      leaderboardChanges.isNotEmpty ||
      roundChanges.isNotEmpty ||
      gameStatsChanges.isNotEmpty;

  int get changedLeaderboardEntriesCount => leaderboardChanges.length;

  int get changedRoundEntriesCount => roundChanges.length;

  int get changedGameStatsEntriesCount => gameStatsChanges.length;

  int get changedTippersCount {
    final changedTippers = <String>{};
    for (final change in leaderboardChanges) {
      changedTippers.add(change.tipperDbKey ?? change.tipperName);
    }
    for (final change in roundChanges) {
      changedTippers.add(change.tipperDbKey ?? change.tipperName);
    }
    return changedTippers.length;
  }

  int get rankMoveCount =>
      leaderboardChanges.where((change) => change.rankDelta != 0).length;

  String get summaryLine {
    if (!hasChanges) {
      return 'No scoring changes detected.';
    }

    final parts = <String>[
      '$changedTippersCount ${changedTippersCount == 1 ? 'tipper' : 'tippers'} changed',
    ];

    if (changedLeaderboardEntriesCount > 0) {
      parts.add(
        '$changedLeaderboardEntriesCount leaderboard ${changedLeaderboardEntriesCount == 1 ? 'entry' : 'entries'}',
      );
    }
    if (changedRoundEntriesCount > 0) {
      parts.add(
        '$changedRoundEntriesCount round ${changedRoundEntriesCount == 1 ? 'entry' : 'entries'}',
      );
    }
    if (changedGameStatsEntriesCount > 0) {
      parts.add(
        '$changedGameStatsEntriesCount game stat ${changedGameStatsEntriesCount == 1 ? 'entry' : 'entries'}',
      );
    }
    if (rankMoveCount > 0) {
      parts.add('$rankMoveCount rank ${rankMoveCount == 1 ? 'move' : 'moves'}');
    }

    return parts.join(' • ');
  }
}
