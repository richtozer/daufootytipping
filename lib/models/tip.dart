import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/tipper.dart';

class Tip implements Comparable<Tip> {
  String? dbkey;
  final Game game; //the game being tipped
  final Tipper tipper; //the tipper
  final GameResult tip; //their tip
  final DateTime submittedTimeUTC; //the time the tip was submitted

  Tip(
      {this.dbkey,
      required this.game,
      required this.tipper,
      required this.tip,
      required this.submittedTimeUTC});

  factory Tip.fromJson(
      Map<String, dynamic> data, String key, Tipper tipper, Game game) {
    return Tip(
        dbkey: key,
        game: game,
        tipper: tipper,
        tip: GameResult.values.byName(data['gameResult']),
        submittedTimeUTC: DateTime.parse(data['submittedTimeUTC']));
  }

  toJson() {
    return {
      //'gameDbkey': game.dbkey, // save to the database as a reference
      //'tipperDbkey': tipper.dbkey, //save to the database as a reference
      'gameResult': tip.name,
      'submittedTimeUTC': submittedTimeUTC.toString(),
    };
  }

  @override
  // method used to provide default sort for Tips in a List[]
  int compareTo(Tip other) {
    return submittedTimeUTC.compareTo(other.submittedTimeUTC);
  }
}
