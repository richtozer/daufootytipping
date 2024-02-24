class LeaderboardEntry {
  int rank;
  String name;
  int total;
  int nRL;
  int aFL;
  int numRoundsWon;
  int aflMargins;
  int aflUPS;
  int nrlMargins;
  int nrlUPS;

  int? sortColumnIndex;
  bool isAscending = false;

  //constructor
  LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.total,
    required this.nRL,
    required this.aFL,
    required this.numRoundsWon,
    required this.aflMargins,
    required this.aflUPS,
    required this.nrlMargins,
    required this.nrlUPS,
  });
}
