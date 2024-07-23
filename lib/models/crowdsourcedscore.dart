class CrowdSourcedScore {
  final DateTime submittedTimeUTC;
  final String tipperID;
  final ScoringTeam scoreTeam;
  final int interimScore;
  final bool gameComplete;

  //constructor
  const CrowdSourcedScore(this.submittedTimeUTC, this.scoreTeam, this.tipperID,
      this.interimScore, this.gameComplete);

  //tojson method
  Map<String, dynamic> toJson() {
    return {
      'submittedTimeUTC': submittedTimeUTC.toIso8601String(),
      'tipperID': tipperID,
      'scoreTeam': scoreTeam.name,
      'interimScore': interimScore,
      'gameComplete': gameComplete,
    };
  }

  //fromjson method
  factory CrowdSourcedScore.fromJson(Map data) {
    return CrowdSourcedScore(
      DateTime.parse(data['submittedTimeUTC']),
      ScoringTeam.values.byName(data['scoreTeam']),
      data['tipperID'],
      data['interimScore'],
      data['gameComplete'] as bool,
    );
  }
}

enum ScoringTeam { home, away }
