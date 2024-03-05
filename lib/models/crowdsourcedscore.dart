import 'package:daufootytipping/models/tipper.dart';

class CrowdSourcedScore {
  DateTime submittedTimeUTC;
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;
  bool gameComplete;

  //constructor
  CrowdSourcedScore(this.submittedTimeUTC, this.tipper, this.scoreTeam,
      this.interimScore, this.gameComplete);

  //tojson method
  Map<String, dynamic> toJson() {
    return {
      'submittedTimeUTC': submittedTimeUTC,
      'tipper': tipper.toJson(),
      'scoreTeam': scoreTeam.toString(),
      'interimScore': interimScore,
      'gameComplete': gameComplete,
    };
  }

  //fromjson method
  factory CrowdSourcedScore.fromJson(Map<String, dynamic> data, Tipper tipper) {
    return CrowdSourcedScore(
      data['submittedTimeUTC'],
      tipper,
      data['scoreTeam'],
      data['interimScore'],
      data['gameComplete'],
    );
  }
}

enum ScoreTeam { home, away }
