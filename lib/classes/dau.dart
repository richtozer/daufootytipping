import 'dart:html';

import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:json_annotation/json_annotation.dart';

const tippersPath = '/Tippers';
const teamsPath = '/Teams';
const dauCompsPath = '/DAUComps';

class DAUComp {
  final String? id;
  final String year;
  //List<DAURound> dauRounds = [];
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;

  //constructor
  DAUComp(this.id, this.year, this.aflFixtureJsonURL, this.nrlFixtureJsonURL);

  Map<String, dynamic> toMap() {
    return {
      'year': year,
      //'dauRounds': dauRounds,
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
    };
  }

  DAUComp.fromDocumentSnapshot(DocumentSnapshot<Map<String, dynamic>> doc)
      : id = doc.id,
        year = doc.data()!["year"],
        //dauRounds =
        //doc.data()?["dauRounds"] = doc.data()?["dauRounds"].cast<List>(),
        aflFixtureJsonURL = doc.data()!["aflFixtureJsonURL"],
        nrlFixtureJsonURL = doc.data()!["nrlFixtureJsonURL"];
}

class DAURound {
  final int roundNumber;
  final DateTime roundStartTimeUTC;
  final DateTime roundEndTimeUTC;

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

  String scoreUuid =
      const Uuid().v7(); // create a time based UUID for this score instance
  DateTime submittedTimeUTC = DateTime.now();
  Tipper tipper;
  ScoreTeam scoreTeam;
  int interimScore;
}

enum ScoreTeam { home, away }

enum League { nrl, afl }

enum GameResult { a, b, c, d, e, z }

class Team {
  final String name;
  final Uri logoURI;
  final String teamUuid;

  //constructor
  Team(this.name, this.logoURI, this.teamUuid);
}

// TipperRole - in database admin=1, tipper=2
enum TipperRole { admin, tipper }

class Tipper {
  final String? uid;
  final String authuid;
  final String email;
  final String name;
  final bool active;
  final TipperRole tipperRole;

  //constructor
  Tipper(
      {this.uid,
      required this.authuid,
      required this.email,
      required this.name,
      required this.active,
      required this.tipperRole});

  factory Tipper.fromJson(Map<String, dynamic> data) {
    return Tipper(
        uid: data['hello'],
        authuid: data['authuid'] ?? '',
        email: data['email'] ?? '',
        name: data['name'] ?? '',
        active: data['active'] ?? false,
        tipperRole: TipperRole.values.byName(data['tipperRole']));
  }

  toJson() {
    return {
      "authuid": authuid,
      "email": email,
      "name": name,
      "active": active,
      "tipperRole": tipperRole.name
    };
  }
}
