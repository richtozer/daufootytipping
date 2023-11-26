import 'dart:convert';
import 'dart:developer';
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

//TODO this code has issues on chome web app - add conditional code
// to not use fixture services when running on web

class FixtureDownloadService {
  FixtureDownloadService();
  Future<List<Game>> getLeagueFixture(Uri endpoint, League league) async {
    final dio = Dio(BaseOptions(
        headers: {'Content-Type': 'application/json; charset=UTF-8'}));

    // if we are debuging code? if so, mock the JSON fixture services
    if (!kReleaseMode) {
      final dioAdapter = DioAdapter(dio: dio);
      dioAdapter.onGet(
        endpoint.path,
        (server) => server.reply(
          200,
          '[{"MatchNumber":10,"RoundNumber":1,"DateUtc":"2024-03-16 09:10:00Z","Location":"Heritage Bank Stadium","HomeTeam":"Gold Coast Suns","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":15,"RoundNumber":2,"DateUtc":"2024-03-22 08:40:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Geelong Cats","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":24,"RoundNumber":3,"DateUtc":"2024-03-29 08:20:00Z","Location":"Optus Stadium","HomeTeam":"Fremantle","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":30,"RoundNumber":4,"DateUtc":"2024-04-04 08:40:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Melbourne","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":42,"RoundNumber":5,"DateUtc":"2024-04-13 06:35:00Z","Location":"Marvel Stadium","HomeTeam":"Carlton","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":48,"RoundNumber":6,"DateUtc":"2024-04-19 09:40:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Essendon","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":59,"RoundNumber":7,"DateUtc":"2024-04-27 03:45:00Z","Location":"Blundstone Arena","HomeTeam":"North Melbourne","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":64,"RoundNumber":8,"DateUtc":"2024-05-02 09:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Port Adelaide","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":81,"RoundNumber":9,"DateUtc":"2024-05-12 06:00:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Brisbane Lions","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":84,"RoundNumber":10,"DateUtc":"2024-05-18 03:45:00Z","Location":"MCG","HomeTeam":"Collingwood","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":99,"RoundNumber":11,"DateUtc":"2024-05-26 06:40:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"West Coast Eagles","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":102,"RoundNumber":12,"DateUtc":"2024-06-01 03:45:00Z","Location":"MCG","HomeTeam":"Hawthorn","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":107,"RoundNumber":13,"DateUtc":"2024-06-06 09:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Richmond","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":118,"RoundNumber":14,"DateUtc":"2024-06-15 09:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Sydney Swans","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":134,"RoundNumber":16,"DateUtc":"2024-06-28 02:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"GWS Giants","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":136,"RoundNumber":17,"DateUtc":"2024-07-05 02:00:00Z","Location":"Gabba","HomeTeam":"Brisbane Lions","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":152,"RoundNumber":18,"DateUtc":"2024-07-12 02:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"St Kilda","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":156,"RoundNumber":19,"DateUtc":"2024-07-19 02:00:00Z","Location":"Marvel Stadium","HomeTeam":"Essendon","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":170,"RoundNumber":20,"DateUtc":"2024-07-26 02:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Hawthorn","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":174,"RoundNumber":21,"DateUtc":"2024-08-02 02:00:00Z","Location":"GMHBA Stadium","HomeTeam":"Geelong Cats","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":188,"RoundNumber":22,"DateUtc":"2024-08-09 02:30:00Z","Location":"Adelaide Oval","HomeTeam":"Adelaide Crows","AwayTeam":"Western Bulldogs","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":197,"RoundNumber":23,"DateUtc":"2024-08-16 02:30:00Z","Location":"Adelaide Oval","HomeTeam":"Port Adelaide","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null},{"MatchNumber":205,"RoundNumber":24,"DateUtc":"2024-08-23 02:00:00Z","Location":"SCG","HomeTeam":"Sydney Swans","AwayTeam":"Adelaide Crows","Group":null,"HomeTeamScore":null,"AwayTeamScore":null}]',
          // simulate real network delay of 1 second before returning data.
          delay: const Duration(seconds: 1),
        ),
      );
    }

    final response = await dio.get(endpoint.path);

    //log('response code: ${response.statusCode} \n body: ${response.data}');

    if (response.statusCode == 200) {
      final List<dynamic> decodedJsonList =
          jsonDecode(response.data.toString());
      List<Game> games = decodedJsonList
          .map((gameAsJSON) => fromFixtureJson(gameAsJSON, League.afl))
          .toList();
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
}
