import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class DAURoundsPage extends StatefulWidget {
  const DAURoundsPage({super.key});

  @override
  State<DAURoundsPage> createState() => _DAURoundsPageState();
}

class _DAURoundsPageState extends State<DAURoundsPage> {
  @override
  void initState() {
    super.initState();
    initDAURounds();
  }

  Map<int, List<Game>> _nestedGroups =
      {}; // TODO this pattern does not use late - see if I can refactor older code the same?

  initDAURounds() async {
    _nestedGroups = await Provider.of<TipsViewModel>(context, listen: false)
        .gamesViewModel
        .nestedGames;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TipsViewModel>(
        builder: (context, tipsViewModel, child) {
          return ListView.builder(
            itemCount: _nestedGroups.length,
            itemBuilder: (context, index) {
              var combinedRoundNumber = _nestedGroups.keys.elementAt(index);
              var games = _nestedGroups[combinedRoundNumber];

              return ExpansionTile(
                title:
                    Text('Round: $combinedRoundNumber Total: ${games!.length}'),
                children: games.map((game) {
                  return ListTile(
                    title:
                        Text('${game.homeTeam.name} v ${game.awayTeam.name}'),
                    subtitle: Text(
                        '${DateFormat('EEE dd MMM hh:mm a').format(game.startTimeUTC.toLocal())} - ${game.location}'),
                    // Add more properties of the game as needed
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
