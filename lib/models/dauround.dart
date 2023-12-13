
/*
import 'package:daufootytipping/models/game.dart';

class DAURound {
  List<Game> games = [];

  String? dbkey;
  final String dAUroundName;
  final int aflRoundNumber;
  final int nrlRoundNumber;
  //DateTime?
  //    roundEndTimeUTC; //typically around midnight (AEST) - on the day of the last game. In UTC lets say 16h00 to be safe

  // counstructor
  DAURound(
      {this.dbkey,
      required this.dAUroundName,
//      required this.roundEndTimeUTC,
      required this.aflRoundNumber,
      required this.nrlRoundNumber});

  factory DAURound.fromJson(Map<String, dynamic> data, String? key) {
    return DAURound(
      dbkey: key,
      dAUroundName: data['dAUroundName'] ?? '',
      aflRoundNumber: data['aflRoundNumber'] ?? 0,
      nrlRoundNumber: data['nrlRoundNumber'] ?? 0,
      //     roundEndTimeUTC: data['roundEndTimeUTC'],
    );
  }

  Map toJson() => {
        'dAUroundName': dAUroundName,
//        'roundEndTimeUTC': roundEndTimeUTC,
        'aflRoundNumber': aflRoundNumber,
        'nrlRoundNumber': nrlRoundNumber,
      };

  //TODO consider removing
  /* @override
  // method used to provide default sort for DAURounds in a List[]
  int compareTo(DAURound other) {
    return roundEndTimeUTC.compareTo(other.roundEndTimeUTC);
  }
  */
}
*/