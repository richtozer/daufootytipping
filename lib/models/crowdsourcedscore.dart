import 'package:daufootytipping/models/tipper.dart';
import 'package:uuid/uuid.dart';

class CroudSourcedScore {
  //constructor
  CroudSourcedScore(this.tipper, this.scoreTeam, this.interimScore);

  String scoreUuid =
      const Uuid().v7(); // create a time based UUID for this score instance
  DateTime submittedTimeUTC = DateTime.now();
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;
}

enum ScoreTeam { home, away }

enum GameResult { a, b, c, d, e, z }
