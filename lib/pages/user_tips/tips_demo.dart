import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class AdminGamePage extends StatelessWidget {
  static const String route = '/AdminGames';
  const AdminGamePage({super.key});

  Future<List<Game>> getGameList() async {
    const League league = League.afl;

    final dio = Dio(BaseOptions(
        headers: {'Content-Type': 'application/json; charset=UTF-8'}));

    final response =
        await dio.get('https://fixturedownload.com/feed/json/afl-2024');

    if (response.statusCode == 200) {
      List<dynamic> res = response.data;
      List<Game> games =
          res.map((gameAsJson) => fromFixtureJson(gameAsJson, league)).toList();
      return games;
    }
    throw Exception('Could not get the league fixture list');
  }

  Game fromFixtureJson(Map<String, dynamic> data, League league) {
    return Game(
      dbkey:
          '${league.name}-${data['RoundNumber']}-${data['MatchNumber']}', //create a unique based on league, roune number and match number
      league: league,
      homeTeam: Team(
          name: data['HomeTeam'],
          dbkey: '${league.name}-${data['HomeTeam']}',
          league: league),
      awayTeam: Team(
          name: data['AwayTeam'],
          dbkey: '${league.name}-${data['AwayTeam']}',
          league: league),
      location: data['Location'] ?? '',
      startTimeUTC: DateTime.parse(data['DateUtc']),
      roundNumber: data['RoundNumber'] ?? 0,
      matchNumber: data['MatchNumber'] ?? 0,
      scoring: (data['HomeTeamScore'] != null && data['AwayTeamScore'] != null)
          ? Scoring(
              homeTeamScore: data['HomeTeamScore'] as int,
              awayTeamScore: data['AwayTeamScore'] as int)
          : null, // if we have official scores then add them to a scoring object
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: const Text('Admin Home'),
        ),
        body: FutureBuilder<List<Game>>(
            future: getGameList(),
            builder: (context, snapshot) {
              print("snapshot");
              print(snapshot.data);
              if (snapshot.hasData) {
                final List<Game> games = snapshot.data!;
                return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListView.builder(
                        itemCount: snapshot.data?.length,
                        itemBuilder: (BuildContext context, int i) {
                          return Card(
                            child: Container(
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      width: 0.5, color: Colors.grey)),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Column(
                                  children: <Widget>[
                                    Text(
                                        '${games[i].homeTeam.name} - ${games[i].awayTeam.name}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }));
              } else if (snapshot.hasError) {
                return Text("${snapshot.error}");
              }

              // By default, show a loading spinner.
              return const CircularProgressIndicator();
            }));
  }
}
