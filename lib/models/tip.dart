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

  Tip({
    this.dbkey,
    required this.game,
    required this.tipper,
    required this.tip,
    required this.submittedTimeUTC,
  });

  bool isDefaultTip() {
    return (submittedTimeUTC ==
        DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true));
  }

  factory Tip.fromJson(Map data, String key, Tipper tipper, Game game) {
    return Tip(
      dbkey: key,
      game: game,
      tipper: tipper,
      // Read new short keys first, then fall back to legacy names
      tip: GameResult.values.byName(
        (data['r'] ?? data['gameResult']) as String,
      ),
      submittedTimeUTC: (() {
        final dynamic raw = data['t'] ?? data['submittedTimeUTC'];
        if (raw is int) {
          // Epoch seconds (compact)
          return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
        } else if (raw is String) {
          // Try numeric epoch seconds string, else ISO-8601 string
          final int? asInt = int.tryParse(raw);
          if (asInt != null) {
            return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
          }
          return DateTime.parse(raw);
        } else {
          // Fallback: treat as now UTC if unexpected
          return DateTime.now().toUtc();
        }
      })(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // Write using compact field names to conserve database space
      'r': tip.name,
      // Store as epoch seconds (int) to reduce size and precision
      't': submittedTimeUTC.millisecondsSinceEpoch ~/ 1000,
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
      game.league,
      game.scoring!.getGameResultCalculated(game.league),
      tip,
    );
  }

  int getMaxScoreCalculated() {
    return Scoring.getTipScoreCalculated(
      game.league,
      game.scoring!.getGameResultCalculated(game.league),
      game.scoring!.getGameResultCalculated(game.league),
    );
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
