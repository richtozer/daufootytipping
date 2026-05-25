class RoundStats {
  int roundNumber = 0;
  int aflPoints = 0;
  int aflMaxPoints = 0;
  int aflMarginTips = 0;
  int aflMarginUPS = 0;
  int nrlPoints = 0;
  int nrlMaxPoints = 0;
  int nrlMarginTips = 0;
  int nrlMarginUPS = 0;
  int rank = 0;
  int rankChange = 0;
  int nrlTipsOutstanding = 0;
  int aflTipsOutstanding = 0;

  //constructor
  RoundStats({
    required this.roundNumber,
    required this.aflPoints,
    required this.aflMaxPoints,
    required this.aflMarginTips,
    required this.aflMarginUPS,
    required this.nrlPoints,
    required this.nrlMaxPoints,
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
      'aS': aflPoints,
      'aMs': aflMaxPoints,
      'aMt': aflMarginTips,
      'aMu': aflMarginUPS,
      'nS': nrlPoints,
      'nMs': nrlMaxPoints,
      'nMt': nrlMarginTips,
      'nMu': nrlMarginUPS,
      'nTo': nrlTipsOutstanding,
      'aTo': aflTipsOutstanding,
    };
  }

  factory RoundStats.fromJson(
    Map<String, dynamic> data, {
    int fallbackRoundNumber = 0,
  }) {
    return RoundStats(
      roundNumber: data['nbr'] ?? fallbackRoundNumber,
      aflPoints: data['aS'] ?? 0,
      aflMaxPoints: data['aMs'] ?? 0,
      aflMarginTips: data['aMt'] ?? 0,
      aflMarginUPS: data['aMu'] ?? 0,
      nrlPoints: data['nS'] ?? 0,
      nrlMaxPoints: data['nMs'] ?? 0,
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
      aflPoints,
      aflMaxPoints,
      aflMarginTips,
      aflMarginUPS,
      nrlPoints,
      nrlMaxPoints,
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
        other.aflPoints == aflPoints &&
        other.aflMaxPoints == aflMaxPoints &&
        other.aflMarginTips == aflMarginTips &&
        other.aflMarginUPS == aflMarginUPS &&
        other.nrlPoints == nrlPoints &&
        other.nrlMaxPoints == nrlMaxPoints &&
        other.nrlMarginTips == nrlMarginTips &&
        other.nrlMarginUPS == nrlMarginUPS &&
        other.nrlTipsOutstanding == nrlTipsOutstanding &&
        other.aflTipsOutstanding == aflTipsOutstanding;
  }

  @override
  int get hashCode {
    return roundNumber.hashCode ^
        aflPoints.hashCode ^
        aflMaxPoints.hashCode ^
        aflMarginTips.hashCode ^
        aflMarginUPS.hashCode ^
        nrlPoints.hashCode ^
        nrlMaxPoints.hashCode ^
        nrlMarginTips.hashCode ^
        nrlMarginUPS.hashCode ^
        nrlTipsOutstanding.hashCode ^
        aflTipsOutstanding.hashCode;
  }
}
