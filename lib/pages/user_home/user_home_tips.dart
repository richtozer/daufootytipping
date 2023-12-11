import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TippingList extends StatelessWidget {
  const TippingList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TipsViewModel>(
        builder: (context, tipsViewModel, child) {
          return CustomScrollView(
            slivers: <Widget>[
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    final game = tipsViewModel.games[index];
                    return Card(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(width: 0.5, color: Colors.grey),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            children: <Widget>[
                              Text(
                                '${game.startTimeUTC.toLocal()}-${game.location}-${game.homeTeam.name} - ${game.awayTeam.name} - Tip: ${tipsViewModel.getLatestGameTip(game.dbkey)?.tip.toString()}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              ElevatedButton(
                                child: const Text('Your Tip'),
                                onPressed: () {
                                  Tip tip = Tip(
                                    tipper: Provider.of<TippersViewModel>(
                                            context,
                                            listen: false)
                                        .tippers[Provider.of<TippersViewModel>(
                                            context,
                                            listen: false)
                                        .currentTipperIndex],
                                    game: game,
                                    tip: GameResult.c,
                                    submittedTimeUTC: DateTime.now(),
                                  );

                                  tipsViewModel.addTip(tip);
                                },
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: tipsViewModel.games.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
