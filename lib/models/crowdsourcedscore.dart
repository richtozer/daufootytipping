import 'package:daufootytipping/models/tipper.dart';

class CroudSourcedScore {
  DateTime submittedTimeUTC = DateTime.now();
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;

  //constructor
  CroudSourcedScore(this.tipper, this.scoreTeam, this.interimScore);
}

enum ScoreTeam { home, away }
