import 'package:daufootytipping/models/game.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/view_models/gametip_viewmodel.dart';

class GameInfo extends StatelessWidget {
  const GameInfo(this.game, this.gameTipsViewModel, {super.key});

  final Game game;
  final GameTipViewModel gameTipsViewModel;

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
              if (gameTipsViewModel.tip != null &&
                  gameTipsViewModel.tip!.isDefaultTip() == false)
                Text(
                  style: Theme.of(context).textTheme.labelSmall,
                  'Tipped:${DateFormat('dd/MM hh:mm a').format(gameTipsViewModel.tip!.submittedTimeUTC.toLocal())}',
                ),
              if (gameTipsViewModel.tip != null &&
                  gameTipsViewModel.tip!.isDefaultTip() == true)
                Text(
                  style: Theme.of(context).textTheme.labelSmall,
                  'Default tip of [Away] given',
                ),

              Text(
                style: Theme.of(context).textTheme.labelSmall,
                'Kickoff:${DateFormat('dd MMM hh:mm a').format(game.startTimeUTC.toLocal())}',
              ),

              Flexible(
                child: Text(
                  gameTipsViewModel.game.location,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),

              Text(
                style: Theme.of(context).textTheme.labelSmall,
                'Fixture: round ${gameTipsViewModel.game.fixtureRoundNumber}, match ${gameTipsViewModel.game.fixtureMatchNumber}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
