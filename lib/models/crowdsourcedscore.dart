import 'package:daufootytipping/models/tipper.dart';

class CroudSourcedScore {
  DateTime submittedTimeUTC = DateTime.now().toUtc();
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;

  //constructor
  CroudSourcedScore(this.tipper, this.scoreTeam, this.interimScore);

  //tojson method
  Map<String, dynamic> toJson() {
    return {
      'submittedTimeUTC': submittedTimeUTC,
      'tipper': tipper.toJson(),
      'scoreTeam': scoreTeam.toString(),
      'interimScore': interimScore,
    };
  }

  //fromjson method
  factory CroudSourcedScore.fromJson(Map<String, dynamic> data, Tipper tipper) {
    return CroudSourcedScore(
      tipper,
      data['scoreTeam'] == 'home' ? ScoreTeam.home : ScoreTeam.away,
      data['interimScore'],
    );
  }
}

enum ScoreTeam { home, away }
