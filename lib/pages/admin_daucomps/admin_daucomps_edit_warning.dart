import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/services/rounds_linking_service.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const String kUnassignedGamesWarningTitle =
    'Warning: Unassigned Games Detected!';
const String kUnassignedGamesWarningMessage =
    'The following games have kickoff dates before the regular comp cutoff (if supplied), but are not assigned to any round.\n\nPlease modify the round dates to include these game(s).\n\nEach item is in the following format: \n- League-LeagueRoundNumber-MatchNumber HomeTeam v AwayTeam (Kickoff time):';
const String kSplitRoundGamesWarningTitle =
    'Warning: Split League Round Games Detected!';
const String kSplitRoundGamesWarningMessage =
    'The following upcoming games are assigned to a different DAU round from most of their league round.\n\nMove the round start date if you want to keep the league round together.';

class AdminDaucompsEditWarning extends StatelessWidget {
  final String title;
  final String message;
  final List<String> lines;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;

  const AdminDaucompsEditWarning({
    super.key,
    required this.title,
    required this.message,
    required this.lines,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
  });

  factory AdminDaucompsEditWarning.unassigned({
    Key? key,
    required List<Game> games,
  }) {
    return AdminDaucompsEditWarning(
      key: key ?? const ValueKey('unassigned-games-warning'),
      title: kUnassignedGamesWarningTitle,
      message: kUnassignedGamesWarningMessage,
      lines: [
        for (final game in games)
          '- ${game.league.name}-${game.fixtureRoundNumber}-${game.fixtureMatchNumber} '
              '${game.homeTeam.name} v ${game.awayTeam.name} '
              '(${DateFormat('yyyy-MM-dd HH:mm').format(game.startTimeUTC.toLocal())})',
      ],
      backgroundColor: Colors.red[50]!,
      borderColor: Colors.red,
      titleColor: Colors.red,
    );
  }

  factory AdminDaucompsEditWarning.splitRound({
    Key? key,
    required List<SplitRoundGame> splitGames,
  }) {
    return AdminDaucompsEditWarning(
      key: key ?? const ValueKey('split-round-games-warning'),
      title: kSplitRoundGamesWarningTitle,
      message: kSplitRoundGamesWarningMessage,
      lines: [
        for (final entry in splitGames)
          '- ${entry.game.league.name}-${entry.game.fixtureRoundNumber}-${entry.game.fixtureMatchNumber} '
              '${entry.game.homeTeam.name} v ${entry.game.awayTeam.name} '
              '(${DateFormat('yyyy-MM-dd HH:mm').format(entry.game.startTimeUTC.toLocal())}) '
              '- in DAU Round ${entry.assignedRoundNumber}, home DAU Round ${entry.homeRoundNumber}',
      ],
      backgroundColor: Colors.amber[50]!,
      borderColor: Colors.amber[800]!,
      titleColor: Colors.amber[900]!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(kCardCornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
          ),
          const SizedBox(height: 8.0),
          Text(message, style: const TextStyle(color: Colors.black)),
          const SizedBox(height: 8.0),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return Text(
                lines[index],
                style: const TextStyle(color: Colors.black),
              );
            },
          ),
        ],
      ),
    );
  }
}
