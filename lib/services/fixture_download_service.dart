import 'dart:developer';
import 'package:daufootytipping/models/fixture.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class FixtureDownloadService {
  FixtureDownloadService();

  Future<Map<String, List<dynamic>>> fetch(
      List<Fixture> fixtures, bool downloadOnSeparateThread) async {
    if (fixtures.isEmpty) {
      throw ArgumentError('The list of fixtures cannot be empty.');
    }

    // we can only pass simple data types to the background isolate
    Map<String, dynamic> simpleFixtures = {
      'fixtureJsonURLs':
          fixtures.map((f) => f.fixtureJsonURL.toString()).toList()
    };

    Map<String, dynamic> result;

    if (!downloadOnSeparateThread) {
      result = await fetchFixtures(simpleFixtures);
      log('Fixture data loaded on MAIN thread.');
    } else {
      result = await compute(fetchFixtures, simpleFixtures);
      log('Fixture data loaded on BACKGROUND thread.');
    }

    if (result.containsKey('error')) {
      throw Exception(result['error']);
    }

    return result.map((key, value) => MapEntry(key, value as List<dynamic>));
  }

  Future<Map<String, dynamic>> fetchFixtures(
      Map<String, dynamic> simpleDAUComp) async {
    Map<String, List<dynamic>> fixtures = {};
    String errorMessage = '';

    for (String url in simpleDAUComp['fixtureJsonURLs']) {
      try {
        Uri uri = Uri.parse(url);
        List<dynamic> games =
            await FixtureDownloadService.getLeagueFixtureRaw(uri);
        fixtures[url] = games;
      } catch (e) {
        errorMessage =
            'Error loading fixture data from $url. Exception was: $e';
        break;
      }
    }

    if (errorMessage.isNotEmpty) {
      return {'error': errorMessage};
    }

    return fixtures;
  }

  static Future<List<dynamic>> getLeagueFixtureRaw(Uri endpoint) async {
    final dio = Dio(BaseOptions(
        headers: {'Content-Type': 'application/json; charset=UTF-8'}));

    final response = await dio.get(endpoint.toString());

    if (response.statusCode == 200) {
      List<dynamic> res = response.data;
      return res;
    }
    throw Exception(
        'Could not receive the league fixture list: ${endpoint.toString()}');
  }
}
