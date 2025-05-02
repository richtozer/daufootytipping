class GameStatsEntry {
  double? percentageTippedHomeMargin = 0.0;
  double? percentageTippedHome = 0.0;
  double? percentageTippedDraw = 0.0;
  double? percentageTippedAway = 0.0;
  double? percentageTippedAwayMargin = 0.0;
  double? averageScore = 0.0;

  //constructor
  GameStatsEntry({
    this.percentageTippedHomeMargin,
    this.percentageTippedHome,
    this.percentageTippedDraw,
    this.percentageTippedAway,
    this.percentageTippedAwayMargin,
    this.averageScore,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GameStatsEntry &&
        other.percentageTippedHomeMargin == percentageTippedHomeMargin &&
        other.percentageTippedHome == percentageTippedHome &&
        other.percentageTippedDraw == percentageTippedDraw &&
        other.percentageTippedAway == percentageTippedAway &&
        other.percentageTippedAwayMargin == percentageTippedAwayMargin &&
        other.averageScore == averageScore;
  }

  @override
  int get hashCode {
    return percentageTippedHomeMargin.hashCode ^
        percentageTippedHome.hashCode ^
        percentageTippedDraw.hashCode ^
        percentageTippedAway.hashCode ^
        percentageTippedAwayMargin.hashCode ^
        averageScore.hashCode;
  }

  // method to convert instance into json
  Map<String, dynamic> toJson() {
    return {
      'pctTipA': percentageTippedHomeMargin,
      'pctTipB': percentageTippedHome,
      'pctTipC': percentageTippedDraw,
      'pctTipD': percentageTippedAway,
      'pctTipE': percentageTippedAwayMargin,
      'avgScore': averageScore,
    };
  }

  // method to convert json into instance
  factory GameStatsEntry.fromJson(Map<String, dynamic> data) {
    return GameStatsEntry(
      percentageTippedHomeMargin: (data['pctTipA'] as num?)?.toDouble(),
      percentageTippedHome: (data['pctTipB'] as num?)?.toDouble(),
      percentageTippedDraw: (data['pctTipC'] as num?)?.toDouble(),
      percentageTippedAway: (data['pctTipD'] as num?)?.toDouble(),
      percentageTippedAwayMargin: (data['pctTipE'] as num?)?.toDouble(),
      averageScore: (data['avgScore'] as num?)?.toDouble(),
    );
  }
}
