class LadderTeam {
  String dbkey;
  String teamName;
  String? logoURI;
  int played;
  int won;
  int lost;
  int drawn;
  int pointsFor;
  int pointsAgainst;
  int points;
  double percentage;
  int? originalRank; // Made non-final

  LadderTeam({
    required this.dbkey,
    required this.teamName,
    this.logoURI,
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.drawn = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
    this.points = 0,
    this.percentage = 0.0,
    this.originalRank, // Add to constructor
  });

  void calculatePercentage() {
    if (pointsAgainst == 0) {
      if (pointsFor == 0) {
        percentage = 0.0;
      } else {
        percentage =
            pointsFor * 100.0; // Or a very high fixed number if preferred
      }
    } else {
      percentage = (pointsFor / pointsAgainst) * 100.0;
    }
  }
}
