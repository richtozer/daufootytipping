import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';

class TipHistoryEntry {
  final String gameId;
  final League league;
  final int year;
  final int roundNumber;
  final String homeTeamName;
  final String awayTeamName;
  final String? homeTeamLogoUri;
  final String? awayTeamLogoUri;
  final GameResult tip;
  final DateTime tipSubmittedUTC;
  final String? submittedBy;

  const TipHistoryEntry({
    required this.gameId,
    required this.league,
    required this.year,
    required this.roundNumber,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.homeTeamLogoUri,
    required this.awayTeamLogoUri,
    required this.tip,
    required this.tipSubmittedUTC,
    this.submittedBy,
  });
}
