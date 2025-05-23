// lib/models/team_game_history_item.dart

class TeamGameHistoryItem {
  final String opponentName;
  final String? opponentLogoUri;
  final int teamScore; // Score of the team for whom the history is being viewed
  final int opponentScore;
  final String result; // "W", "L", "D" (relative to the team)
  final int ladderPoints; // Points earned by the team from this game
  final DateTime gameDate;
  final int roundNumber;

  TeamGameHistoryItem({
    required this.opponentName,
    this.opponentLogoUri,
    required this.teamScore,
    required this.opponentScore,
    required this.result,
    required this.ladderPoints,
    required this.gameDate,
    required this.roundNumber,
  });
}
