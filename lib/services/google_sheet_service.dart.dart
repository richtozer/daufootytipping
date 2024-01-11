import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gsheets/gsheets.dart';

/* 
https://itnext.io/dart-working-with-google-sheets-793ed322daa0
*/

class LegacyTippingService {
  final Completer<void> _initialLoadCompleter = Completer<void>();

  late final GSheets gsheets;
  late final Worksheet sheet;
  late final List<List<String>> rows;

  final String? spreadsheetId = dotenv.env['DAU_GSHEET_ID'];

  final String sheetName = 'AppTips';

  LegacyTippingService() {
    _initialize(spreadsheetId!, sheetName);
  }

  Future<void> _initialize(String spreadsheetId, String sheetName) async {
    //TODO remove private key from code
    var credentials = {
      "type": "service_account",
      "project_id": dotenv.env['PROJECT_ID'],
      "private_key_id": dotenv.env['PRIVATE_KEY_ID'],
      "private_key":
          "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC+WAd7eZ3U9EU6\nAqCkYIBqE9buYBejA1vQm3V+tsfTSpR7OXFZqtXjUlrIP48TmtGOoTgZEUgFdIE0\nqnTKe4Ufnm98+g0wg1vDDAoJ2f9zSS4U54larHFDAYIUfV2m2k5rUvlMH4Sl352x\nJfgw/xg/VaSC18CL6Ho1yYyFoGliyIWTb0GvKaeeKcZnd8pxEPTfToFCuPu1I+HY\n7G/14kx7meCrSiPJXnOSq4R6DHApBAm5IKsBxQm/pL2MPbe4X4hM63APx54kVij2\n+m+4DoP67Fs1gr6Jcri49Uw9QD/XGUVJ1CGWHkw+/gD+eBKpZDYYgXLWIwiH39k5\nIUs3flMrAgMBAAECggEAXHTS8Zmh3jJmu+ZR1HZheeU4JeK8KHz1qK8Sk+HBz3Kv\nC+nbkrQGH9y9Zv5kh5/QgYjzAE4iHzA3oHbZsw7rm2+wdNLa/EEaHfRnneBrkjqu\nLQ5IbChN/b+qSTyZ9HWe2MfdeynmG1IyvT0VwOrwAredaMbW6r6aOi0z2iaQeh/Y\nwqm9cHgTTQt2884QmN1g5SiI5hz9EjDVOfW+tesemU6EQu8Kuh8Y2WN7wifEa3Ck\ngLc/Ea4GwjtPeGUKh0qd1cd+SrOU3zc46bgqq60rT3X3AevQG9/jhZb2mRA0JheR\ngyS1+dPWRw3E3HKJ//DS7lrrZ91mac9N3wHvgVm0dQKBgQDr3756fPi7tZwP5tZ0\nT2CsGLDK5rXkWPnQwqwHtyJjU5fFNYLl//x1V0slvN+348y0PS+UOZhJHq3J+6r1\nNaq1nj2pCVjmDYJwiY0cPZjTsHjXso7Ig5z7jf8yxF9r/v2LBG9AEzX/SJsDeUPO\ngm7FNq7uiTZCKJqroUsnkK0M5QKBgQDOlcJAkN4avTbEvxVBoi1mtRC34M3M7WOC\noqiLLnyEFkVheQZWG569zQHs7PiewH9BsLbfLmTXPYfeKetH8Cqt3yPteLtzItIY\nTYIinxRcwlhHv98SdQ26IdeNEcZ+J+0GFn4DxPDEkdTDUdyga6Eks0cAM/DB5CLD\n/kA7LgTuzwKBgQDP2B/LZVX0aepz5K/yW4PPAg6/LB75cSHov7HBNrGZnq5s+2M1\n8qTubRZt0Ym9S4E1DXlgfoPfYqY3Bom1ey3Kzf59dhwc06iuK7bpPKnvV2CUiOXi\ncH8i9xP6EyoWSuH13tl9N7BsG/lkTTXfwfWD2FS7IrNqBseMFxvXaFfktQKBgHUB\nj29AXfvpFV8kFycAcxSMEzcCZa3e+pCgDjQelTm+33cQtA0LQcKgnamSolJQFwOe\n0kTgIw9h81Vair9JAPNPwiqbShgxLavEIqP3U/IhxRyGSRNMJwU4a7yjx7fmZzIe\nhSsfXXsIWehysjJOI4wE2n777C31R9eYZsreCr8zAoGBANuHKD+ax9Acs0yUYKJ8\nphbdbc0oNUENm7EvGt+X8HOe262XyzwhtBGzbelNX5qjCHDzbUHqhaTiSV9gWCk1\nZLIS9XqSRmSL2gRd5ENlTJpsGulwLBAJaDL/muTbbq23RnV6iTmkIZErKvHxRWsi\nCWCapx/tX67zRMnDnE6l+xKT\n-----END PRIVATE KEY-----\n",
      "client_email": dotenv.env['CLIENT_EMAIL'],
      "client_id": dotenv.env['CLIENT_ID'],
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url":
          "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url":
          "https://www.googleapis.com/robot/v1/metadata/x509/sheets%40dau-footy-tipping-f8a42.iam.gserviceaccount.com",
      "universe_domain": "googleapis.com"
    };

    // Get authenticated client
    gsheets = GSheets(credentials);

    final spreadsheet = await gsheets.spreadsheet(spreadsheetId);
    sheet = spreadsheet.worksheetByTitle(sheetName)!;

    // Get all rows from the sheet
    rows = await sheet.values.allRows();

    if (!_initialLoadCompleter.isCompleted) {
      _initialLoadCompleter.complete();
    }

    log('Initial legacy gsheet load complete. Found ${rows.length} rows.');
  }

  Future<void> submitDefaultTips(
      String tipperName, GamesViewModel gamesViewModel) async {
    await _initialLoadCompleter.future;
    log('Initial legacy gsheet load complete. submitDefaultTips()');

    //get the total number of combined rounds
    List<int> combinedRounds = await gamesViewModel.getCombinedRoundNumbers();

    //udate the header row, from column c, with the combined rounds numbers
    await sheet.values.insertRow(1, combinedRounds, fromColumn: 3);

    int currentCombinedRound = await gamesViewModel
        .getCurrentCombinedRoundNumber(); //TODO test what happens when this increments

    // Find the row with the matching TipperName
    final rowToUpdate = rows.indexWhere((row) => row[0] == tipperName);

    List<String> existingTips = [];

    if (rowToUpdate == -1) {
      // If a matching row is not found, throw exception
      throw Exception(
          'Tipper $tipperName cannot be found in the legacy tipping sheet AppTips tab');
    } else {
      //make sure we preserve any existing tips in the sheet, before we update the row with the default tips
      //starting from column of the current round + 2 (as the first two columns are the tipper name and the comp name)

      for (var combinedRound in combinedRounds.sublist(currentCombinedRound)) {
        if (rows[rowToUpdate].length > 2) {
          existingTips.add(rows[rowToUpdate][combinedRound]);
        } else {
          existingTips.add(''); //TODO test this
        }
      }
    }

    // loop through the combinedRounds from the GamesViewmodel starting at the current combined round and create default tips
    List<String> newDefaultTips = [];
    for (int roundNumber in combinedRounds.sublist(currentCombinedRound - 1)) {
      String defaultTips = await gamesViewModel
          .getDefaultTipsForCombinedRoundNumber(roundNumber);
      newDefaultTips.add(defaultTips);
    }

    // compare existingTips with newDefaultTips:
    //  1) If the entire row is the same, character for charactor, then don't update the row
    //  2) If they are different, note the poistion of the "a","b","c","d" and "e" tips and make sure they are preserved in the update.
    //  Any 'D' or 'z' tips can be overwritten as needed in the update
    if (existingTips.join() == newDefaultTips.join()) {
      log('No change to default tips for $tipperName');
      return;
    } else {
      // loop through the existingTips and preserve any 'a','b','c','d' or 'e' tips
      for (int i = 0; i < existingTips.length; i++) {
        for (int j = 0; j < 17; j++) {
          if (existingTips[i][j] == 'a' ||
              existingTips[i][j] == 'b' ||
              existingTips[i][j] == 'c' ||
              existingTips[i][j] == 'd' ||
              existingTips[i][j] == 'e') {
            newDefaultTips[i].replaceRange(j, j + 1, existingTips[i][j]);
          }
        }
      }

      int maxAttempts = 5;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          await sheet.values.insertRow(rowToUpdate + 1, newDefaultTips,
              fromColumn: currentCombinedRound + 2);
          break; // If the request is successful, break out of the loop
        } catch (e) {
          log('Error ${e.toString()} submitting default tips for $tipperName, attempt $attempt of $maxAttempts');
          await Future.delayed(
              const Duration(seconds: 10)); // Wait for 60 seconds
        }
      }
    }
  }

  Future<void> saveToGoogleSheets(List<Map<String, dynamic>> rows) async {
    int maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await sheet.values.map.appendRows(rows);
        break; // If the request is successful, break out of the loop
      } catch (e) {
        log('Error ${e.toString()} submitting default tips for all tippers');

        await Future.delayed(const Duration(seconds: 5)); // Wait for 5 seconds
      }
    }
  }

  Future<void> submitTips(String tipperName, String nrlTips, String aflTips,
      int dauRoundNumber) async {
    await _initialLoadCompleter.future;
    log('Initial legacy gsheet load complete. submitTips()');
// Find the row with the matching TipperName
    final rowToUpdate = rows.indexWhere((row) => row[0] == tipperName);

    if (rowToUpdate == -1) {
      // If a matching row is not found, throw exception
      throw Exception(
          'Tipper $tipperName cannot be found in the legacy tipping sheet AppTips tab');
    } else {
      // update existing row
      await sheet.values.insertRow(rowToUpdate + 1, [nrlTips + aflTips],
          fromColumn: dauRoundNumber + 2);
    }
  }
}

/*
  factory Product.fromGsheets(Map<String, dynamic> json) {
    return Product(
      id: int.tryParse(json['id'] ?? ''),
      name: json['name'],
      quantity: int.tryParse(json['quantity'] ?? ''),
      price: double.tryParse(json['price'] ?? ''),
    );
  }

  Map<String, dynamic> toGsheets() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'price': price,
    };
  }

*/
