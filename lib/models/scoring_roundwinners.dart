import 'package:daufootytipping/models/tipper.dart';

class RoundWinnerEntry {
  int roundNumber;
  Tipper tipper;
  int total;
  int nRL;
  int aFL;
  int aflMargins;
  int aflUPS;
  int nrlMargins;
  int nrlUPS;

  int? sortColumnIndex;
  bool isAscending = false;

  //constructor
  RoundWinnerEntry({
    required this.roundNumber,
    required this.tipper,
    required this.total,
    required this.nRL,
    required this.aFL,
    required this.aflMargins,
    required this.aflUPS,
    required this.nrlMargins,
    required this.nrlUPS,
  });
}
