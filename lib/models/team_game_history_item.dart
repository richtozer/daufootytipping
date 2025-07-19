// lib/models/team_game_history_item.dart

class TeamGameHistoryItem {
  final String opponentName;
  final String? opponentLogoUri;
  final int teamScore; // Score of the team for whom the history is being viewed
  final int opponentScore;
  final String result; // "Won", "Lost", "Draw" (relative to the team)
  final int ladderPoints; // Points earned by the team from this game
  final DateTime gameDate;
  final int roundNumber;
  final String? competitionName; // Name of the competition/year for grouping
  final bool isHomeGame; // Whether the team was playing at home

  TeamGameHistoryItem({
    required this.opponentName,
    this.opponentLogoUri,
    required this.teamScore,
    required this.opponentScore,
    required this.result,
    required this.ladderPoints,
    required this.gameDate,
    required this.roundNumber,
    this.competitionName,
    required this.isHomeGame,
  });
}
