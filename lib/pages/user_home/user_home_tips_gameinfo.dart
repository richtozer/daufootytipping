import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';

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
              game.gameState == GameState.startedResultKnown
                  ? Text(DateFormat('EEE dd MMM yyyy')
                      .format(game.startTimeUTC.toLocal()))
                  : Text(DateFormat('EEE dd MMM hh:mm a')
                      .format(game.startTimeUTC.toLocal())),
              Flexible(
                child: Text(
                  gameTipsViewModel.game.location,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${gameTipsViewModel.game.league == League.afl ? 'AFL' : 'NRL'} round: ${gameTipsViewModel.game.roundNumber}',
              ),
              // if the tipper has tipped, or they can been given a defaul tip
              // then display the tip submitted time in their local time
              // if they have yet to tip, then display nothing
              if (gameTipsViewModel.tipGame != null &&
                  gameTipsViewModel.tipGame!.isDefaultTip() == false)
                Text(
                  'Tipped: ${DateFormat('EEE dd MMM hh:mm a').format(gameTipsViewModel.tipGame!.submittedTimeUTC.toLocal())}',
                ),
              if (gameTipsViewModel.tipGame != null &&
                  gameTipsViewModel.tipGame!.isDefaultTip() == true)
                const Text(
                  'Default tip of [Away] given',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
