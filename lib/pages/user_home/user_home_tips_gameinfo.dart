import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_home/user_home_tips_gamelistitem.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daufootytipping/pages/user_home/gametips_viewmodel.dart';

class GameInfo extends StatelessWidget {
  const GameInfo({
    super.key,
    required this.widget,
    required this.gameTipsViewModel,
  });

  final GameListItem widget;
  final GameTipsViewModel gameTipsViewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(DateFormat('EEE dd MMM hh:mm a')
                  .format(widget.game.startTimeUTC.toLocal())),
              Flexible(
                child: Text(
                  gameTipsViewModel.game.location,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${gameTipsViewModel.game.league == League.afl ? 'AFL' : 'NRL'} round: ${gameTipsViewModel.game.roundNumber}',
              ),
              Text(
                'lat/lng ${gameTipsViewModel.getLatLng()}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
