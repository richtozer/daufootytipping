class RoundScores {
  int roundNumber = 0;
  int aflScore = 0;
  int aflMaxScore = 0;
  int aflMarginTips = 0;
  int aflMarginUPS = 0;
  int nrlScore = 0;
  int nrlMaxScore = 0;
  int nrlMarginTips = 0;
  int nrlMarginUPS = 0;
  int rank = 0;
  int rankChange = 0;

//contructor
  RoundScores({
    required this.roundNumber,
    required this.aflScore,
    required this.aflMaxScore,
    required this.aflMarginTips,
    required this.aflMarginUPS,
    required this.nrlScore,
    required this.nrlMaxScore,
    required this.nrlMarginTips,
    required this.nrlMarginUPS,
    required this.rank,
    required this.rankChange,
  });

  toJson() {
    return {
      'roundNumber': roundNumber,
      'afl_score': aflScore,
      'afl_maxScore': aflMaxScore,
      'afl_marginTips': aflMarginTips,
      'afl_marginUPS': aflMarginUPS,
      'nrl_score': nrlScore,
      'nrl_maxScore': nrlMaxScore,
      'nrl_marginTips': nrlMarginTips,
      'nrl_marginUPS': nrlMarginUPS,
      // 'rank': rank,
      // 'changeInRank': rankChange,
    };
  }

  factory RoundScores.fromJson(Map<String, dynamic> data) {
    return RoundScores(
      roundNumber: data['roundNumber'] ?? 0,
      aflScore: data['afl_score'] ?? 0,
      aflMaxScore: data['afl_maxScore'] ?? 0,
      aflMarginTips: data['afl_marginTips'] ?? 0,
      aflMarginUPS: data['afl_marginUPS'] ?? 0,
      nrlScore: data['nrl_score'] ?? 0,
      nrlMaxScore: data['nrl_maxScore'] ?? 0,
      nrlMarginTips: data['nrl_marginTips'] ?? 0,
      nrlMarginUPS: data['nrl_marginUPS'] ?? 0,
      rank: 0,
      rankChange: 0,
    );
  }

  toCsv() {
    return [
      aflScore,
      aflMaxScore,
      aflMarginTips,
      aflMarginUPS,
      nrlScore,
      nrlMaxScore,
      nrlMarginTips,
      nrlMarginUPS,
      rank,
      rankChange,
    ];
  }

  // compare two roundscores using == operator
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RoundScores &&
        other.roundNumber == roundNumber &&
        other.aflScore == aflScore &&
        other.aflMaxScore == aflMaxScore &&
        other.aflMarginTips == aflMarginTips &&
        other.aflMarginUPS == aflMarginUPS &&
        other.nrlScore == nrlScore &&
        other.nrlMaxScore == nrlMaxScore &&
        other.nrlMarginTips == nrlMarginTips &&
        other.nrlMarginUPS == nrlMarginUPS;
  }

  @override
  int get hashCode {
    return roundNumber.hashCode ^
        aflScore.hashCode ^
        aflMaxScore.hashCode ^
        aflMarginTips.hashCode ^
        aflMarginUPS.hashCode ^
        nrlScore.hashCode ^
        nrlMaxScore.hashCode ^
        nrlMarginTips.hashCode ^
        nrlMarginUPS.hashCode;
  }
}
