import 'dart:developer';
import 'package:collection/collection.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final Uri aflFixtureJsonURL;
  final Uri nrlFixtureJsonURL;
  List<DAURound> daurounds;
  final bool active;

  DateTime? lastFixtureUpdateTimestamp;

  //constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.aflFixtureJsonURL,
    required this.nrlFixtureJsonURL,
    this.active = true,
    required this.daurounds,
    this.lastFixtureUpdateTimestamp,
  });

  // method to return the highest round number, where DAURound.RoundState is allGamesEnded
  int getHighestRoundNumberWithAllGamesPlayed() {
    int highestRoundNumber = 1;

    for (var dauround in daurounds) {
      if (dauround.roundState == RoundState.allGamesEnded) {
        if (dauround.dAUroundNumber > highestRoundNumber) {
          highestRoundNumber = dauround.dAUroundNumber;
        }
      }
    }
    return highestRoundNumber;
  }

  factory DAUComp.fromJson(
      Map<String, dynamic> data, String? key, List<DAURound> daurounds) {
    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      aflFixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
      nrlFixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
      daurounds: daurounds,
      lastFixtureUpdateTimestamp: data['lastFixtureUpdateTimestamp'] != null
          ? DateTime.parse(data['lastFixtureUpdateTimestamp'])
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
      'active': active,
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
        other.nrlFixtureJsonURL == nrlFixtureJsonURL &&
        other.active == active &&
        other.lastFixtureUpdateTimestamp == lastFixtureUpdateTimestamp &&
        const ListEquality().equals(other.daurounds, daurounds);
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^
        active.hashCode ^
        name.hashCode ^
        aflFixtureJsonURL.hashCode ^
        nrlFixtureJsonURL.hashCode ^
        lastFixtureUpdateTimestamp.hashCode ^
        daurounds.hashCode;
  }
}
