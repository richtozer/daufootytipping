class RoundScores {
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

  factory RoundScores.fromJson(Map<String, dynamic> data) {
    return RoundScores(
      aflScore: data['afl_score'] ?? 0,
      aflMaxScore: data['afl_maxScore'] ?? 0,
      aflMarginTips: data['afl_marginTips'] ?? 0,
      aflMarginUPS: data['afl_marginUPS'] ?? 0,
      nrlScore: data['nrl_score'] ?? 0,
      nrlMaxScore: data['nrl_maxScore'] ?? 0,
      nrlMarginTips: data['nrl_marginTips'] ?? 0,
      nrlMarginUPS: data['nrl_marginUPS'] ?? 0,
      rank: data['rank'] ?? 0,
      rankChange: data['changeInRank'] ?? 0,
    );
  }
}

class CompScore {
  int aflCompScore = 0;
  int aflCompMaxScore = 0;
  int nrlCompScore = 0;
  int nrlCompMaxScore = 0;

//contructor
  CompScore({
    required this.aflCompScore,
    required this.aflCompMaxScore,
    required this.nrlCompScore,
    required this.nrlCompMaxScore,
  });

  factory CompScore.fromJson(Map<String, dynamic> data) {
    return CompScore(
      aflCompScore: data['total_afl_score'] ?? 0,
      aflCompMaxScore: data['total_afl_maxScore'] ?? 0,
      nrlCompScore: data['total_nrl_score'] ?? 0,
      nrlCompMaxScore: data['total_nrl_maxScore'] ?? 0,
    );
  }
}
