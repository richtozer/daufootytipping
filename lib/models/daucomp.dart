import 'package:collection/collection.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/fixture.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class DAUComp implements Comparable<DAUComp> {
  String? dbkey;
  final String name;
  final List<Fixture> fixtures;
  List<DAURound> daurounds;
  DateTime? lastFixtureUpdateTimestamp;

  // Constructor
  DAUComp({
    this.dbkey,
    required this.name,
    required this.fixtures,
    required this.daurounds,
    this.lastFixtureUpdateTimestamp,
  });

  // Return the highest round number where roundEndDate is in the past UTC
  int highestRoundNumberInPast() {
    int highestRoundNumber = 1;

    for (var dauround in daurounds) {
      if (dauround.roundEndDate
          .add(const Duration(hours: 9))
          .isBefore(DateTime.now().toUtc())) {
        if (dauround.dAUroundNumber > highestRoundNumber) {
          highestRoundNumber = dauround.dAUroundNumber;
        }
      }
    }
    return highestRoundNumber;
  }

  // Return the highest round number where all games have ended
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

  // Factory constructor for creating DAUComp instances from JSON
  factory DAUComp.fromJson(
      Map<String, dynamic> data, String? key, List<DAURound> daurounds) {
    return DAUComp(
      dbkey: key,
      name: data['name'] ?? '',
      fixtures:
          data['aflFixtureJsonURL'] != null && data['nrlFixtureJsonURL'] != null
              ? [
                  Fixture(
                    fixtureJsonURL: Uri.parse(data['aflFixtureJsonURL']),
                    league: League.afl,
                  ),
                  Fixture(
                    fixtureJsonURL: Uri.parse(data['nrlFixtureJsonURL']),
                    league: League.nrl,
                  ),
                ]
              : (data['fixtures'] as List<dynamic>)
                  .map((fixtureData) =>
                      Fixture.fromJson(fixtureData as Map<String, dynamic>))
                  .toList(),
      daurounds: daurounds,
      lastFixtureUpdateTimestamp: data['lastFixtureUpdateTimestamp'] != null
          ? DateTime.parse(data['lastFixtureUpdateTimestamp'])
          : null,
    );
  }

  static List<DAUComp> fromJsonList(List<Object?> compDbKeys) {
    List<DAUComp> daucompList = [];
    for (var compDbKey in compDbKeys) {
      di<DAUCompsViewModel>().findComp(compDbKey as String).then((daucomp) {
        if (daucomp != null && daucomp.dbkey == compDbKey) {
          daucompList.add(daucomp);
        }
      });
    }
    return daucompList;
  }

  // Serialize to JSON for comparison purposes
  Map<String, dynamic> toJsonForCompare() {
    List<Map<String, dynamic>> dauroundsJson =
        daurounds.map((dauround) => dauround.toJsonForCompare()).toList();

    List<Map<String, dynamic>> fixturesJson =
        fixtures.map((fixture) => fixture.toJson()).toList();

    return {
      'name': name,
      'fixtures': fixturesJson,
      'daurounds': dauroundsJson,
    };
  }

  @override
  int compareTo(DAUComp other) {
    return name.compareTo(other.name);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DAUComp &&
        other.dbkey == dbkey &&
        other.name == name &&
        const ListEquality().equals(other.fixtures, fixtures);
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^ name.hashCode ^ fixtures.hashCode;
  }
}
