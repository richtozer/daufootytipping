class ConsolidatedScores {
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
  ConsolidatedScores({
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
}

class ConsolidatedCompScores {
  int aflCompScore = 0;
  int aflCompMaxScore = 0;
  int nrlCompScore = 0;
  int nrlCompMaxScore = 0;

//contructor
  ConsolidatedCompScores({
    required this.aflCompScore,
    required this.aflCompMaxScore,
    required this.nrlCompScore,
    required this.nrlCompMaxScore,
  });
}
