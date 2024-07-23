import 'package:daufootytipping/models/game.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/view_models/gametips_viewmodel.dart';

class GameInfo extends StatelessWidget {
  const GameInfo(this.game, this.gameTipsViewModel, {super.key});

  final Game game;
  final GameTipsViewModel gameTipsViewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // if the tipper has tipped, or they can been given a defaul tip
              // then display the tip submitted time in their local time
              // if they have yet to tip, then display nothing
              if (gameTipsViewModel.tipGame != null &&
                  gameTipsViewModel.tipGame!.isDefaultTip() == false)
                Text(
                  style: const TextStyle(fontSize: 12),
                  'You tipped: ${DateFormat('EEE dd MMM hh:mm a').format(gameTipsViewModel.tipGame!.submittedTimeUTC.toLocal())}',
                ),
              // display a line separator here
              const Divider(
                height: 5,
              ),
              if (gameTipsViewModel.tipGame != null &&
                  gameTipsViewModel.tipGame!.isDefaultTip() == true)
                const Text(
                  style: TextStyle(fontSize: 12),
                  'Default tip of [Away] given',
                ),
              game.gameState == GameState.startedResultKnown
                  ? Text(
                      style: const TextStyle(fontSize: 12),
                      DateFormat('EEE dd MMM yyyy')
                          .format(game.startTimeUTC.toLocal()))
                  : Text(
                      style: const TextStyle(fontSize: 12),
                      'Kickoff: ${DateFormat('EEE dd MMM hh:mm a').format(game.startTimeUTC.toLocal())}'),
              Flexible(
                child: Text(
                  gameTipsViewModel.game.location,
                  style: const TextStyle(fontSize: 12),
                ),
              ),

              Text(
                style: const TextStyle(fontSize: 12),
                'Fixture: round ${gameTipsViewModel.game.roundNumber}, match ${gameTipsViewModel.game.matchNumber}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
