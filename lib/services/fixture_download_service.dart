import 'dart:developer';

import 'package:daufootytipping/models/league.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef LeagueFetcher = Future<List<dynamic>> Function(Uri endpoint, League league);

// Default network fetcher used in production code and isolate execution
Future<List<dynamic>> _defaultLeagueFetch(Uri endpoint, League league) async {
  final dio = Dio(
    BaseOptions(headers: {'Content-Type': 'application/json; charset=UTF-8'}),
  );
  final response = await dio.get(endpoint.toString());
  if (response.statusCode == 200) {
    return response.data as List<dynamic>;
  }
  throw Exception(
    'Could not receive the league fixture list: ${endpoint.toString()}',
  );
}

class FixtureDownloadService {
  final LeagueFetcher _fetcher;
  final bool _useIsolateWhenRequested;

  FixtureDownloadService() : _fetcher = _defaultLeagueFetch, _useIsolateWhenRequested = true;

  // Test-only constructor: inject a fetcher and bypass isolate execution for determinism
  FixtureDownloadService.test(LeagueFetcher fetcher)
      : _fetcher = fetcher,
        _useIsolateWhenRequested = false;

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

    if (downloadOnSeparateThread && _useIsolateWhenRequested) {
      // Use isolate-safe top-level function which leverages default network fetcher
      result = await compute(_fetchFixturesOnIsolate, simpleDAUComp);
      log('Fixture data loaded on BACKGROUND thread.');
    } else {
      // Execute on main thread (used in tests and when isolate usage is disabled)
      result = await _fetchFixtures(simpleDAUComp);
      log('Fixture data loaded on MAIN thread.');
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
      nrlGames = await _fetcher(Uri.parse(simpleDAUComp['nrlFixtureJsonURL']), League.nrl);
    } catch (e) {
      errorMessage = 'Error loading NRL fixture data. Exception was: $e';
    }

    if (errorMessage.isEmpty) {
      try {
        aflGames = await _fetcher(Uri.parse(simpleDAUComp['aflFixtureJsonURL']), League.afl);
      } catch (e) {
        errorMessage = 'Error loading AFL fixture data. Exception was: $e';
      }
    }

    if (errorMessage.isNotEmpty) {
      return {'error': errorMessage};
    }

    return {'nrlGames': nrlGames, 'aflGames': aflGames};
  }

}

// Isolate entrypoint uses the default network fetcher
Future<Map<String, dynamic>> _fetchFixturesOnIsolate(
  Map<String, dynamic> simpleDAUComp,
) async {
  List<dynamic> nrlGames = [];
  List<dynamic> aflGames = [];
  String errorMessage = '';

  try {
    nrlGames = await _defaultLeagueFetch(
      Uri.parse(simpleDAUComp['nrlFixtureJsonURL']),
      League.nrl,
    );
  } catch (e) {
    errorMessage = 'Error loading NRL fixture data. Exception was: $e';
  }

  if (errorMessage.isEmpty) {
    try {
      aflGames = await _defaultLeagueFetch(
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
