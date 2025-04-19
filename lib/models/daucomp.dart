import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound> daurounds;
  final List<dynamic>? aflBaseline;
  final List<dynamic>? nrlBaseline;

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
    this.aflBaseline,
    this.nrlBaseline,
  });

  // method to return the highest round number where roundEndDate is the past UTC
  // it does not require gamesviewmodel to fully load all games
  // tips page calls this method ahead of gamesviewmodel loading all games
  // we will add an arbitrary 6 hours to the round end date to ensure the round is considered past
  int highestRoundNumberInPast() {
    int highestRoundNumber = 0;

    //find the highest round number where roundEndDate + 6 hours is the past UTC
    for (var dauround in daurounds) {
      if (dauround.lastGameKickOffUTC
          .add(const Duration(hours: 6))
          .isBefore(DateTime.now().toUtc())) {
        if (dauround.dAUroundNumber > highestRoundNumber) {
          highestRoundNumber = dauround.dAUroundNumber;
        }
      }
    }

    return highestRoundNumber;
  }

  // method to calculate the pixel height up to the supplied round number
  // this is used to scroll the listview to the correct position when the tips page is loaded
  double pixelHeightUpToRound(int roundNumber) {
    double totalHeight = 0;

    // add the height of the welcome header if roundNumber is greater than zero
    if (roundNumber > 0) totalHeight += 200;

    // add height for each round up to the supplied round number
    for (var dauround in daurounds) {
      if (dauround.dAUroundNumber <= roundNumber) {
        // add the height for 2 headers - use DAURound.getGamesForRound to get the games for each league,
        // if league has no games, then use emptyLeagueRoundHeight otherwise use leagueHeaderHeight
        dauround.getGamesForLeague(League.nrl).isEmpty
            ? totalHeight += DAURound.noGamesCardheight
            : dauround.roundState == RoundState.allGamesEnded
                ? totalHeight += DAURound.leagueHeaderEndedHeight
                : totalHeight += DAURound.leagueHeaderHeight;

        dauround.getGamesForLeague(League.afl).isEmpty
            ? totalHeight += DAURound.noGamesCardheight
            : dauround.roundState == RoundState.allGamesEnded
                ? totalHeight += DAURound.leagueHeaderEndedHeight
                : totalHeight += DAURound.leagueHeaderHeight;

        // add the height for all games in the round
        totalHeight += dauround.games.length * Game.gameCardHeight;
      }
    }

    return totalHeight;
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
      lastFixtureUpdateTimestampUTC: data['lastFixtureUTC'] != null
          ? DateTime.parse(data['lastFixtureUTC'])
          : null,
      aflRegularCompEndDateUTC: data['aflRegularCompEndDateUTC'] != null
          ? DateTime.parse(data['aflRegularCompEndDateUTC'])
          : null,
      nrlRegularCompEndDateUTC: data['nrlRegularCompEndDateUTC'] != null
          ? DateTime.parse(data['nrlRegularCompEndDateUTC'])
          : null,
      aflBaseline: data['aflFixtureBaseline'] ?? [],
      nrlBaseline: data['nrlFixtureBaseline'] ?? [],
    );
  }

  static List<DAUComp> fromJsonList(List compDbKeys) {
    // find each DAUComp based on the compDbKeys
    List<DAUComp> daucompList = [];
    for (var compDbKey in compDbKeys) {
      di<DAUCompsViewModel>().findComp(compDbKey).then((daucomp) {
        if (daucomp == null) {
          log('DAUComp.fromJsonList: compDbKey not found: $compDbKey');
        } else {
          if (daucomp.dbkey == compDbKey) {
            daucompList.add(daucomp);
          }
        }
      });
    }

    return daucompList;
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
        other.nrlFixtureJsonURL == nrlFixtureJsonURL &&
        other.lastFixtureUpdateTimestampUTC == lastFixtureUpdateTimestampUTC &&
        other.aflRegularCompEndDateUTC == aflRegularCompEndDateUTC &&
        other.nrlRegularCompEndDateUTC == nrlRegularCompEndDateUTC &&
        const DeepCollectionEquality().equals(other.daurounds, daurounds) &&
        const DeepCollectionEquality().equals(other.nrlBaseline, nrlBaseline) &&
        const DeepCollectionEquality().equals(other.aflBaseline, aflBaseline);
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^
        name.hashCode ^
        aflFixtureJsonURL.hashCode ^
        nrlFixtureJsonURL.hashCode ^
        lastFixtureUpdateTimestampUTC.hashCode ^
        aflRegularCompEndDateUTC.hashCode ^
        nrlRegularCompEndDateUTC.hashCode ^
        const DeepCollectionEquality().hash(daurounds) ^
        const DeepCollectionEquality().hash(nrlBaseline) ^
        const DeepCollectionEquality().hash(aflBaseline);
  }
}
