// Purpose: Service to download fixture from a JSON endpoint
import 'package:daufootytipping/models/game.dart';
import 'package:daufootytipping/models/game_scoring.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/team.dart';
import 'package:daufootytipping/services/fixture_mock_data_2024_afl_full.dart';
import 'package:daufootytipping/services/fixture_mock_data_2024_nrl_full.dart';
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

    // if we are debuging code? if so, mock the JSON fixture services network call
    if (!kReleaseMode) {
      var mockdata;

      switch (endpoint.toString()) {
        case 'https://fixturedownload.com/feed/json/afl-2024':
          mockdata = mockAfl2024Full;
          break;
        case 'https://fixturedownload.com/feed/json/nrl-2024':
          mockdata = mockNrl2024Full;
          break;
        default:
          throw Exception('Could not match the endpoint to a mock data');
      }

      final dioAdapter = DioAdapter(dio: dio);
      dioAdapter.onGet(
        endpoint.toString(),
        (server) => server.reply(
          200,
          mockdata,
          // simulate real network delay of 1 second before returning data.
          delay: const Duration(seconds: 1),
        ),
      );
    }

    final response = await dio.get(endpoint.toString());

    //log('response code: ${response.statusCode} \n body: ${response.data}');

    if (response.statusCode == 200) {
      List<dynamic> res = response.data;
      List<Game> games =
          res.map((gameAsJson) => fromFixtureJson(gameAsJson, league)).toList();
      return games;
    }
    throw Exception(
        'Could not receive the league fixture list: ${endpoint.toString()}');
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
