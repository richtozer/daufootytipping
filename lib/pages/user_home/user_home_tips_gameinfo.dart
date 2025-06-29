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
    String tipText = '';
    if (gameTipsViewModel.tip != null) {
      if (gameTipsViewModel.tip!.isDefaultTip() == true) {
        tipText = 'Default tip of [Away] given';
      } else {
        tipText =
            'Tipped: ${DateFormat('EEE dd MMM hh:mm a').format(gameTipsViewModel.tip!.submittedTimeUTC.toLocal())}';
      }
    }

    final kickoffText = game.gameState != GameState.notStarted
        ? 'Played: ${DateFormat('EEE d MMM').format(game.startTimeUTC.toLocal())}'
        : 'Kickoff: ${DateFormat('EEE dd MMM hh:mm').format(game.startTimeUTC.toLocal())}';
    final locationText = gameTipsViewModel.game.location;
    final fixtureText =
        'Fixture: round ${gameTipsViewModel.game.fixtureRoundNumber}, match ${gameTipsViewModel.game.fixtureMatchNumber}';

    final infoParagraph = [
      if (tipText.isNotEmpty) tipText,
      kickoffText,
      locationText,
      fixtureText,
    ].join(' 🏉 ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          infoParagraph,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
          softWrap: true,
        ),
      ),
    );
  }
}
