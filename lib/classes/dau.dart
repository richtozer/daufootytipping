class DAUComp {
  // commit this and this and this
  String year;
  List<DAURound> dauRounds = [];

  DAUComp(this.year);

  Map toJson() => {
        'year': year,
        'dauRounds': dauRounds,
      };
}

class DAURound {
  int roundNumber;
  DateTime roundStartTimeUTC;
  DateTime roundEndTimeUTC;

  // counstructor
  DAURound(this.roundNumber, this.roundStartTimeUTC, this.roundEndTimeUTC);

  Map toJson() => {
        'roundNumber': roundNumber,
        'roundStartTimeUTC': roundStartTimeUTC,
        'roundEndTimeUTC': roundEndTimeUTC,
      };
}

class Game {
  League league;
  Team homeTeam;
  Team awayTeam;
  String location;
  DateTime startTimeUTC;
  int round;
  int match;
  DAURound dAUround;
  int? homeTeamsScore; // will be null until official score is downloaded
  int? awayTeamScore; // will be null until official score is downloaded
  List<CroudSourcedScore> croudSourcedScores = [];
  int homeTeamOdds;
  int awayTeamOdds;
  GameResult gameResult = GameResult.z; // use 'z' until game result is known

  //constructor
  Game(
      this.league,
      this.homeTeam,
      this.awayTeam,
      this.location,
      this.startTimeUTC,
      this.round,
      this.match,
      this.dAUround,
      this.homeTeamOdds,
      this.awayTeamOdds);
}

class CroudSourcedScore {
  //constructor
  CroudSourcedScore(this.tipper, this.scoreTeam, this.interimScore);

  DateTime submittedTimeUTC = DateTime.now();
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;
}

enum ScoreTeam { home, away }

enum League { nrl, afl }

enum GameResult { a, b, c, d, e, z }

class Team {
  String name;
  String logoURI;

  //constructor
  Team(this.name, this.logoURI);
}

class Tipper {}
