import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

class AdminDaucompsEditWarning extends StatelessWidget {
  final DAUCompsViewModel viewModel;

  const AdminDaucompsEditWarning({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.red[50],
        border: Border.all(color: Colors.red),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Warning: Unassigned Games Detected!',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8.0),
          const Text(
            'The following games have kickoff dates before the regular comp cutoff (if supplied), but are not assigned to any round.\n\nPlease modify the round dates to include these game(s).\n\nEach item is in the following format: \n- League-LeagueRoundNumber-MatchNumber HomeTeam v AwayTeam (Kickoff time):',
            style: TextStyle(color: Colors.black),
          ),
          const SizedBox(height: 8.0),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: viewModel.unassignedGames.length,
            itemBuilder: (context, index) {
              final game = viewModel.unassignedGames[index];
              return Text(
                '- ${game.league.name}-${game.fixtureRoundNumber}-${game.fixtureMatchNumber} ${game.homeTeam.name} v ${game.awayTeam.name} (${DateFormat('yyyy-MM-dd HH:mm').format(game.startTimeUTC.toLocal())})',
                style: const TextStyle(color: Colors.black),
              );
            },
          ),
        ],
      ),
    );
  }
}
