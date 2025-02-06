import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipper.dart';

// each instance of this class represents a tip for a game
class Tip implements Comparable<Tip> {
  String? dbkey;
  final Game game; //the game being tipped
  final Tipper tipper; //the tipper
  final GameResult tip; //their tip
  final bool legacyTip; //true if the tip came from the legacy google form
  final DateTime submittedTimeUTC; //the time the tip was submitted -
  // interesting tidbit, to tell if the tip came from the app or the legacy google form
  // the time stamp will be suttly different.
  // for the app the format is:         2023-12-28 02:21:55.932148Z
  // for the google form the format is: 2024-01-18T04:03:19.095Z

  Tip(
      {this.dbkey,
      required this.game,
      required this.tipper,
      required this.tip,
      required this.submittedTimeUTC,
      this.legacyTip = false});

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
        legacyTip: data['legacyTip'] ?? false);
  }

  toJson() {
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
