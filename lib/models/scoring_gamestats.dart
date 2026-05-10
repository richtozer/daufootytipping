class GameStatsEntry {
  double? percentageTippedHomeMargin;
  double? percentageTippedHome;
  double? percentageTippedDraw;
  double? percentageTippedAway;
  double? percentageTippedAwayMargin;
  double? averageScore;
  int? averageScoreTipCount;

  // Constructor
  GameStatsEntry({
    double? percentageTippedHomeMargin,
    double? percentageTippedHome,
    double? percentageTippedDraw,
    double? percentageTippedAway,
    double? percentageTippedAwayMargin,
    double? averageScore,
    this.averageScoreTipCount,
  }) {
    // Reduce precision to 2 decimal places
    this.percentageTippedHomeMargin = reducePrecision(
      percentageTippedHomeMargin,
    );
    this.percentageTippedHome = reducePrecision(percentageTippedHome);
    this.percentageTippedDraw = reducePrecision(percentageTippedDraw);
    this.percentageTippedAway = reducePrecision(percentageTippedAway);
    this.percentageTippedAwayMargin = reducePrecision(
      percentageTippedAwayMargin,
    );
    this.averageScore = reducePrecision(averageScore);
  }

  // Helper method to reduce precision
  double? reducePrecision(double? value) {
    return value != null ? double.parse(value.toStringAsFixed(3)) : null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GameStatsEntry &&
        other.percentageTippedHomeMargin == percentageTippedHomeMargin &&
        other.percentageTippedHome == percentageTippedHome &&
        other.percentageTippedDraw == percentageTippedDraw &&
        other.percentageTippedAway == percentageTippedAway &&
        other.percentageTippedAwayMargin == percentageTippedAwayMargin &&
        other.averageScore == averageScore &&
        other.averageScoreTipCount == averageScoreTipCount;
  }

  @override
  int get hashCode {
    return percentageTippedHomeMargin.hashCode ^
        percentageTippedHome.hashCode ^
        percentageTippedDraw.hashCode ^
        percentageTippedAway.hashCode ^
        percentageTippedAwayMargin.hashCode ^
        averageScore.hashCode ^
        averageScoreTipCount.hashCode;
  }

  // Method to convert instance into JSON
  Map<String, dynamic> toJson() {
    return {
      'pctTipA': percentageTippedHomeMargin,
      'pctTipB': percentageTippedHome,
      'pctTipC': percentageTippedDraw,
      'pctTipD': percentageTippedAway,
      'pctTipE': percentageTippedAwayMargin,
      'avgScore': averageScore,
      'avgScoreTipCount': averageScoreTipCount,
    };
  }

  // Method to convert JSON into instance
  factory GameStatsEntry.fromJson(Map<String, dynamic> data) {
    return GameStatsEntry(
      percentageTippedHomeMargin: (data['pctTipA'] as num?)?.toDouble(),
      percentageTippedHome: (data['pctTipB'] as num?)?.toDouble(),
      percentageTippedDraw: (data['pctTipC'] as num?)?.toDouble(),
      percentageTippedAway: (data['pctTipD'] as num?)?.toDouble(),
      percentageTippedAwayMargin: (data['pctTipE'] as num?)?.toDouble(),
      averageScore: (data['avgScore'] as num?)?.toDouble(),
      averageScoreTipCount: (data['avgScoreTipCount'] as num?)?.toInt(),
    );
  }
}
