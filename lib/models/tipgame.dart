import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';

// each instance of this class represents a tip for a game
class TipGame implements Comparable<TipGame> {
  String? dbkey;
  final Game game; //the game being tipped
  final Tipper tipper; //the tipper
  final GameResult tip; //their tip
  final DateTime submittedTimeUTC; //the time the tip was submitted -
  // interesting tidbit to tell if the tip came from the app or the legacy google form
  // the time stamp will be suttly different.
  // for the app the format is:         2023-12-28 02:21:55.932148Z
  // for the google form the format is: 2024-01-18T04:03:19.095Z

  TipGame(
      {this.dbkey,
      required this.game,
      required this.tipper,
      required this.tip,
      required this.submittedTimeUTC});

  bool isDefaultTip() {
    return (submittedTimeUTC ==
        DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true));
  }

  factory TipGame.fromJson(Map data, String key, Tipper tipper, Game game) {
    return TipGame(
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

  String getGameResultText() {
    if (game.league == League.nrl) {
      return game.scoring!.getGameResultCalculated(game.league).nrl;
    } else {
      return game.scoring!.getGameResultCalculated(game.league).afl;
    }
  }

  int getTipScoreCalculated() {
    return Scoring.getTipScoreCalculated(
        game.league, game.scoring!.getGameResultCalculated(game.league), tip);
  }

  int getMaxScoreCalculated() {
    return Scoring.getTipScoreCalculated(
        game.league,
        game.scoring!.getGameResultCalculated(game.league),
        game.scoring!.getGameResultCalculated(game.league));
  }

  @override
  // method used to provide default sort for Tips in a List[]
  int compareTo(TipGame other) {
    return submittedTimeUTC.compareTo(other.submittedTimeUTC);
  }
}
