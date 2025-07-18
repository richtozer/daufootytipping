import 'dart:developer';

import 'package:daufootytipping/models/league.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class FixtureDownloadService {
  FixtureDownloadService();

  Future<Map<String, List<dynamic>>> fetch(
    Uri nrlFixtureJsonURL,
    Uri aflFixtureJsonURL,
    bool downloadOnSeparateThread,
  ) async {
    Map<String, dynamic> simpleDAUComp = {
      'nrlFixtureJsonURL': nrlFixtureJsonURL.toString(),
      'aflFixtureJsonURL': aflFixtureJsonURL.toString(),
    };

    Map<String, dynamic> result;

    if (!downloadOnSeparateThread) {
      result = await _fetchFixtures(simpleDAUComp);
      log('Fixture data loaded on MAIN thread.');
    } else {
      result = await compute(_fetchFixtures, simpleDAUComp);
      log('Fixture data loaded on BACKGROUND thread.');
    }

    if (result.containsKey('error')) {
      throw Exception(result['error']);
    }

    return {
      'nrlGames': result['nrlGames'] as List<dynamic>,
      'aflGames': result['aflGames'] as List<dynamic>,
    };
  }

  Future<Map<String, dynamic>> _fetchFixtures(
    Map<String, dynamic> simpleDAUComp,
  ) async {
    List<dynamic> nrlGames = [];
    List<dynamic> aflGames = [];
    String errorMessage = '';

    try {
      nrlGames = await FixtureDownloadService._getLeagueFixtureRaw(
        Uri.parse(simpleDAUComp['nrlFixtureJsonURL']),
        League.nrl,
      );
    } catch (e) {
      errorMessage = 'Error loading NRL fixture data. Exception was: $e';
    }

    if (errorMessage.isEmpty) {
      try {
        aflGames = await FixtureDownloadService._getLeagueFixtureRaw(
          Uri.parse(simpleDAUComp['aflFixtureJsonURL']),
          League.afl,
        );
      } catch (e) {
        errorMessage = 'Error loading AFL fixture data. Exception was: $e';
      }
    }

    if (errorMessage.isNotEmpty) {
      return {'error': errorMessage};
    }

    return {'nrlGames': nrlGames, 'aflGames': aflGames};
  }

  static Future<List<dynamic>> _getLeagueFixtureRaw(
    Uri endpoint,
    League league,
  ) async {
    final dio = Dio(
      BaseOptions(headers: {'Content-Type': 'application/json; charset=UTF-8'}),
    );

    // if we are debuging code? if so, mock the JSON fixture services network call
    /*if (!kReleaseMode) {
      List<Map<String, Object?>> mockdata;

      switch (endpoint.toString()) {
        case 'https://fixturedownload.com/feed/json/afl-2022':
          mockdata = mockAfl2022Full;
          log('Using mockAfl2022Full fixture data');
          break;
        case 'https://fixturedownload.com/feed/json/nrl-2022':
          mockdata = mockNrl2022Full;
          log('Using mockNrl2022Full fixture data');
          break;
        case 'https://fixturedownload.com/feed/json/afl-2023':
          mockdata = mockAfl2023Full;
          //mockdata = mockAfl2023Partial;
          log('Using mockAfl2023Full fixture data');
          break;
        case 'https://fixturedownload.com/feed/json/nrl-2023':
          mockdata = mockNrl2023Full;
          //mockdata = mockNrl2023Partial;
          log('Using mockNrl2023Full fixture data');
          break;
        case 'https://fixturedownload.com/feed/json/afl-2024':
          mockdata = mockAfl2024Full;
          log('Using mockAfl2024Full fixture data');
          break;
        case 'https://fixturedownload.com/feed/json/nrl-2024':
          mockdata = mockNrl2024Full;
          log('Using mockNrl2024Full fixture data');
          break;
        default:
          throw Exception('Could not match the endpoint to mock data');

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
    } */

    final response = await dio.get(endpoint.toString());

    if (response.statusCode == 200) {
      List<dynamic> res = response.data;
      return res;
    }
    throw Exception(
      'Could not receive the league fixture list: ${endpoint.toString()}',
    );
  }
}
