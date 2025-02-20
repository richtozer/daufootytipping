import 'dart:developer';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound> daurounds;
  //final bool active;

  DateTime? lastFixtureUpdateTimestampUTC;
  DateTime?
      aflRegularCompEndDateUTC; // if provided, do not include games in afl fixture after this date
  DateTime?
      nrlRegularCompEndDateUTC; // if provided, do not include games in nrl fixture after this date

  //constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.aflFixtureJsonURL,
    required this.nrlFixtureJsonURL,
    //this.active = true,
    required this.daurounds,
    this.lastFixtureUpdateTimestampUTC,
    this.aflRegularCompEndDateUTC,
    this.nrlRegularCompEndDateUTC,
  });

  // method to return the highest round number where roundEndDate is the past UTC
  // it does not require gamesviewmodel to fully load all games
  // tips page calls this method ahead of gamesviewmodel loading all games
  // because round end date is actually the start time for the last game,
  // we will add an arbitrary 6 hours to the round end date to ensure the round is considered past
  int highestRoundNumberInPast() {
    int highestRoundNumber = 0;

    //find the highest round number where roundEndDate + 6 hours is the past UTC
    for (var dauround in daurounds) {
      if (dauround.roundEndDate
          .add(const Duration(hours: 6))
          .isBefore(DateTime.now().toUtc())) {
        if (dauround.dAUroundNumber > highestRoundNumber) {
          highestRoundNumber = dauround.dAUroundNumber;
        }
      }
    }

    return highestRoundNumber;
  }

  // get lowest round number where RoundState is notStarted or started
  int lowestRoundNumberNotEnded() {
    int lowestRoundNumber = daurounds.length;

    // work backwards from highestRoundNumber to find the lowest round number where roundState is notStarted or started
    for (var i = lowestRoundNumber; i > 0; i--) {
      if (daurounds[i - 1].roundState == RoundState.notStarted ||
          daurounds[i - 1].roundState == RoundState.started) {
        lowestRoundNumber = i;
      } else {
        break;
      }
    }

    return lowestRoundNumber;
  }

  factory DAUComp.fromJson(
      Map<String, dynamic> data, String? key, List<DAURound> daurounds) {
    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      aflFixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
      nrlFixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
      daurounds: daurounds,
      lastFixtureUpdateTimestampUTC: data['lastFixtureUpdateTimestamp'] != null
          ? DateTime.parse(data['lastFixtureUpdateTimestamp'])
          : null,
      aflRegularCompEndDateUTC: data['aflRegularCompEndDateUTC'] != null
          ? DateTime.parse(data['aflRegularCompEndDateUTC'])
          : null,
      nrlRegularCompEndDateUTC: data['nrlRegularCompEndDateUTC'] != null
          ? DateTime.parse(data['nrlRegularCompEndDateUTC'])
          : null,
    );
  }

  static List<DAUComp> fromJsonList(List compDbKeys) {
    // find each DAUComp based on the compDbKeys
    List<DAUComp> daucompList = [];
    for (var compDbKey in compDbKeys) {
      di<DAUCompsViewModel>().findComp(compDbKey).then((daucomp) {
        if (daucomp == null) {
          log('DAUComp.fromJsonList2: compDbKey not found: $compDbKey');
        } else {
          if (daucomp.dbkey == compDbKey) {
            daucompList.add(daucomp);
          }
        }
      });
    }

    return daucompList;
  }

  Map<String, dynamic> toJsonForCompare() {
    // Serialize DAURound list separately
    List<Map<String, dynamic>> dauroundsJson = [];
    for (var dauround in daurounds) {
      dauroundsJson.add(dauround.toJsonForCompare());
    }
    return {
      'name': name,
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
      //'active': active,
      'daurounds': dauroundsJson,
    };
  }

  @override
  // method used to provide default sort for DAUComp(s) in a List[]
  int compareTo(DAUComp other) {
    return name.compareTo(other.name);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DAUComp &&
        other.dbkey == dbkey &&
        other.name == name &&
        other.aflFixtureJsonURL == aflFixtureJsonURL &&
        other.nrlFixtureJsonURL == nrlFixtureJsonURL;
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^
        name.hashCode ^
        aflFixtureJsonURL.hashCode ^
        nrlFixtureJsonURL.hashCode;
  }
}
