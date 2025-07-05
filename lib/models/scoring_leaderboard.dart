import 'package:daufootytipping/models/tipper.dart';

class LeaderboardEntry {
  int rank;
  Tipper tipper;
  int total;
  int nRL;
  int aFL;
  int numRoundsWon;
  int aflMargins;
  int aflUPS;
  int nrlMargins;
  int nrlUPS;
  int? previousRank;
  int? rankChange;

  int? sortColumnIndex;
  bool isAscending = false;

  //constructor
  LeaderboardEntry({
    required this.rank,
    required this.tipper,
    required this.total,
    required this.nRL,
    required this.aFL,
    required this.numRoundsWon,
    required this.aflMargins,
    required this.aflUPS,
    required this.nrlMargins,
    required this.nrlUPS,
    this.previousRank,
    this.rankChange,
  });

  // method to convert instance into json
  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'tipper': tipper.name,
      'total': total,
      'nRL': nRL,
      'aFL': aFL,
      'numRoundsWon': numRoundsWon,
      'aflMargins': aflMargins,
      'aflUPS': aflUPS,
      'nrlMargins': nrlMargins,
      'nrlUPS': nrlUPS,
      'previousRank': previousRank,
      'rankChange': rankChange,
    };
  }
}
