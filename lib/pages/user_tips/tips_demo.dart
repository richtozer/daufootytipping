import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GamesList extends StatelessWidget {
  static const String route = '/GamesList';

  const GamesList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body:
        Consumer<GamesViewModel>(builder: (context, gamesViewModel, child) {
      return ListView(children: [
        ...gamesViewModel.games.map((game) => Card(
                child: Container(
              decoration: BoxDecoration(
                  border: Border.all(width: 0.5, color: Colors.grey)),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: <Widget>[
                    Text(
                        '${game.startTimeUTC}-${game.location}-${game.homeTeam.name} - ${game.awayTeam.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )))
      ]);
    }));
  }
}
