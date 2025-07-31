class RoundStats {
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
  int nrlTipsOutstanding = 0;
  int aflTipsOutstanding = 0;

  //constructor
  RoundStats({
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
    required this.nrlTipsOutstanding,
    required this.aflTipsOutstanding,
  });

  Map<String, int> toJson() {
    return {
      // keep the keys short to save $/space in db
      'nbr': roundNumber,
      'aS': aflScore,
      'aMs': aflMaxScore,
      'aMt': aflMarginTips,
      'aMu': aflMarginUPS,
      'nS': nrlScore,
      'nMs': nrlMaxScore,
      'nMt': nrlMarginTips,
      'nMu': nrlMarginUPS,
      'nTo': nrlTipsOutstanding,
      'aTo': aflTipsOutstanding,
    };
  }

  factory RoundStats.fromJson(Map<String, dynamic> data) {
    return RoundStats(
      roundNumber: data['nbr'] ?? 0,
      aflScore: data['aS'] ?? 0,
      aflMaxScore: data['aMs'] ?? 0,
      aflMarginTips: data['aMt'] ?? 0,
      aflMarginUPS: data['aMu'] ?? 0,
      nrlScore: data['nS'] ?? 0,
      nrlMaxScore: data['nMs'] ?? 0,
      nrlMarginTips: data['nMt'] ?? 0,
      nrlMarginUPS: data['nMu'] ?? 0,
      rank: 0,
      rankChange: 0,
      nrlTipsOutstanding: data['nTo'] ?? 0,
      aflTipsOutstanding: data['aTo'] ?? 0,
    );
  }

  List<int> toCsv() {
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
      nrlTipsOutstanding,
      aflTipsOutstanding,
    ];
  }

  // compare two roundstats using == operator
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RoundStats &&
        other.roundNumber == roundNumber &&
        other.aflScore == aflScore &&
        other.aflMaxScore == aflMaxScore &&
        other.aflMarginTips == aflMarginTips &&
        other.aflMarginUPS == aflMarginUPS &&
        other.nrlScore == nrlScore &&
        other.nrlMaxScore == nrlMaxScore &&
        other.nrlMarginTips == nrlMarginTips &&
        other.nrlMarginUPS == nrlMarginUPS &&
        other.nrlTipsOutstanding == nrlTipsOutstanding &&
        other.aflTipsOutstanding == aflTipsOutstanding;
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
        nrlMarginUPS.hashCode ^
        nrlTipsOutstanding.hashCode ^
        aflTipsOutstanding.hashCode;
  }
}
