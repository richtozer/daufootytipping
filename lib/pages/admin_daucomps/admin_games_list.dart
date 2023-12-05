import 'package:flutter/material.dart';
import 'package:daufootytipping/models/game.dart';

class GamesList extends StatelessWidget {
  final List<Game> games;

  const GamesList({super.key, required this.games});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: games.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(
              '${games[index].homeTeam.name} vs ${games[index].awayTeam.name}'),
          subtitle: Text(
              'Location: ${games[index].location}\nStart Time: ${games[index].startTimeUTC}'),
        );
      },
    );
  }
}
