import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';

// each instance of this class represents a tip for a game
class Tip implements Comparable<Tip> {
  String? dbkey;
  final Game game; //the game being tipped
  Tipper tipper; //the tipper
  final GameResult tip; //their tip
  final DateTime submittedTimeUTC;

  Tip(
      {this.dbkey,
      required this.game,
      required this.tipper,
      required this.tip,
      required this.submittedTimeUTC});

  bool isDefaultTip() {
    return (submittedTimeUTC ==
        DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true));
  }

  factory Tip.fromJson(Map data, String key, Tipper tipper, Game game) {
    return Tip(
      dbkey: key,
      game: game,
      tipper: tipper,
      tip: GameResult.values.byName(data['gameResult']),
      submittedTimeUTC: DateTime.parse(data['submittedTimeUTC']),
    );
  }

  Map<String, String> toJson() {
    return {
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
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Tip &&
        other.dbkey == dbkey &&
        other.game.dbkey == game.dbkey &&
        other.tipper.dbkey == tipper.dbkey &&
        other.tip == tip &&
        other.submittedTimeUTC == submittedTimeUTC;
  }

  @override
  int get hashCode {
    return dbkey.hashCode ^
        game.dbkey.hashCode ^
        tipper.dbkey.hashCode ^
        tip.hashCode ^
        submittedTimeUTC.hashCode;
  }

  @override
  // method used to provide default sort for Tips in a List[]
  int compareTo(Tip other) {
    return submittedTimeUTC.compareTo(other.submittedTimeUTC);
  }
}
