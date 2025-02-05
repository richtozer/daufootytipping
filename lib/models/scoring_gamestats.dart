class GameStatsEntry {
  double? percentageTippedHomeMargin = 0.0;
  double? percentageTippedHome = 0.0;
  double? percentageTippedDraw = 0.0;
  double? percentageTippedAway = 0.0;
  double? percentageTippedAwayMargin = 0.0;

  //constructor
  GameStatsEntry({
    this.percentageTippedHomeMargin,
    this.percentageTippedHome,
    this.percentageTippedDraw,
    this.percentageTippedAway,
    this.percentageTippedAwayMargin,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GameStatsEntry &&
        other.percentageTippedHomeMargin == percentageTippedHomeMargin &&
        other.percentageTippedHome == percentageTippedHome &&
        other.percentageTippedDraw == percentageTippedDraw &&
        other.percentageTippedAway == percentageTippedAway &&
        other.percentageTippedAwayMargin == percentageTippedAwayMargin;
  }

  @override
  int get hashCode {
    return percentageTippedHomeMargin.hashCode ^
        percentageTippedHome.hashCode ^
        percentageTippedDraw.hashCode ^
        percentageTippedAway.hashCode ^
        percentageTippedAwayMargin.hashCode;
  }

  // method to convert instance into json
  Map<String, dynamic> toJson() {
    return {
      'percentageTippedHomeMargin': percentageTippedHomeMargin,
      'percentageTippedHome': percentageTippedHome,
      'percentageTippedDraw': percentageTippedDraw,
      'percentageTippedAway': percentageTippedAway,
      'percentageTippedAwayMargin': percentageTippedAwayMargin,
    };
  }

  // method to convert json into instance
  factory GameStatsEntry.fromJson(Map<String, dynamic> data) {
    return GameStatsEntry(
      percentageTippedHomeMargin: data['percentageTippedHomeMargin'],
      percentageTippedHome: data['percentageTippedHome'],
      percentageTippedDraw: data['percentageTippedDraw'],
      percentageTippedAway: data['percentageTippedAway'],
      percentageTippedAwayMargin: data['percentageTippedAwayMargin'],
    );
  }
}
