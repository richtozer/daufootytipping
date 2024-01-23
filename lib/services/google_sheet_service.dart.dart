import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:gsheets/gsheets.dart';

/* 
https://itnext.io/dart-working-with-google-sheets-793ed322daa0
*/

class LegacyTippingService {
  final Completer<void> _initialLoadCompleter = Completer<void>();

  late final GSheets gsheets;
  final String? spreadsheetId = dotenv.env['DAU_GSHEET_ID'];
  late final SheetsApi sheetsApi;

  late final Worksheet appTipsSheet;
  late final List<List<Object?>>? appTipsData;
  final String appTipsSheetName = 'AppTips';

  late final Worksheet tippersSheet;
  late List<List<String>> tippersRows;
  final String tippersSheetName = 'Tippers';

  LegacyTippingService() {
    // Initialize gsheets here
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

    _initialize();
  }

  Future<void> _initialize() async {
    final spreadsheet = await gsheets.spreadsheet(spreadsheetId!);
    appTipsSheet = spreadsheet.worksheetByTitle(appTipsSheetName)!;
    tippersSheet = spreadsheet.worksheetByTitle(tippersSheetName)!;

    await refresh();
  }

  Future<void> refresh() async {
    try {
      // Fetch updated data for both sheets

      //aptips
      AutoRefreshingAuthClient client = await gsheets.client;
      sheetsApi = SheetsApi(client);
      final values = await sheetsApi.spreadsheets.values.get(
        spreadsheetId!,
        appTipsSheetName,
      );
      appTipsData = values.values;

      log('Sheet ${appTipsSheet.title} data synced. Found ${appTipsData!.length} rows.');

      tippersRows = await tippersSheet.values.allRows();
      log('Initial legacy gsheet load of sheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

      if (!_initialLoadCompleter.isCompleted) {
        _initialLoadCompleter.complete();
        log('LegacyTippingService - Initial legacy gsheet load complete.');
      }
    } catch (e) {
      log('Error refreshing sheets: ${e.toString()}');
    }
  }

  //method to convert gsheet rows of tippers into a list of Tipper objects
  Future<List<Tipper>> getLegacyTippers() async {
    await _initialLoadCompleter.future;
    log('Initial legacy gsheet load complete. getTippers()');

    List<Tipper> tippers = [];

    for (var row in tippersRows) {
      Tipper tipper = Tipper(
          authuid: row[1].toLowerCase(),
          email: row[1]
              .toLowerCase(), // make sure we store the email in lowercase, for later consitent searching
          name: row[0],
          tipperID: row[
              4], //this is the primary key to support lecacy tipping service
          active: row[2] == 'Admin' || row[2] == 'Form' ? true : false,
          tipperRole: row[2] == 'Admin' ? TipperRole.admin : TipperRole.tipper);

      tippers.add(tipper);
    }

    return tippers;
  }

  Future<void> submitDefaultTips(
      List<Tipper> tippers, GamesViewModel gamesViewModel) async {
    await _initialLoadCompleter.future;
    log('Initial legacy gsheet load complete. submitDefaultTips()');

    //get the total number of combined rounds
    List<int> combinedRounds = await gamesViewModel.getCombinedRoundNumbers();

    // Example: Modify a specific cell
    // appTipsData[rowIndex][columnIndex] = 'New Value';

    // only update default tips for future rounds, ignore past rounds
    int currentCombinedRound = await gamesViewModel
        .getCurrentCombinedRoundNumber(); //TODO test what happens when this increments

    for (Tipper tipper in tippers) {
      // Find the row with the matching TipperName
      final rowToUpdate =
          appTipsData!.indexWhere((row) => row[0] == tipper.name);

      if (rowToUpdate == -1) {
        // If a matching row is not found, throw exception
        throw Exception(
            'Tipper ${tipper.name} cannot be found in the legacy tipping sheet AppTips tab');
      }

      // loop through the combinedRounds from the GamesViewmodel starting at the current combined round and create default tips
      List<String> newDefaultTips = [];
      for (int roundNumber
          in combinedRounds.sublist(currentCombinedRound - 1)) {
        String defaultTips = await gamesViewModel
            .getDefaultTipsForCombinedRoundNumber(roundNumber);
        newDefaultTips.add(defaultTips);
      }

      // compare existingTips with newDefaultTips:
      for (int i = 2; i < combinedRounds.length + 2; i++) {
        //have we reached end of the row of tips?
        if (appTipsData![rowToUpdate].length <= (i + 1)) {
          // if we have then extend the row with new default tips
          appTipsData![rowToUpdate].add(newDefaultTips[i - 2]);
        }
        for (int j = 0; j < 17; j++) {
          if (appTipsData![rowToUpdate][i].toString()[j] == 'a' ||
              appTipsData?[rowToUpdate][i].toString()[j] == 'b' ||
              appTipsData?[rowToUpdate][i].toString()[j] == 'c' ||
              appTipsData?[rowToUpdate][i].toString()[j] == 'd' ||
              appTipsData?[rowToUpdate][i].toString()[j] == 'e') {
            newDefaultTips[i].replaceRange(
                j, j + 1, appTipsData![rowToUpdate][i].toString()[j]);
          }
        }
      }
      // testing - only do the first tipper
      break;
    }

    // prepare the updated data for batch load into the gsheet
    List<RowData> rowDataList = [];
    for (List<Object?> row in appTipsData!) {
      rowDataList.add(RowData(
          values: row
              .map((value) => CellData(
                  userEnteredValue:
                      ExtendedValue(stringValue: value?.toString())))
              .toList()
              .sublist(
                  2) //remove the first 2 columns as we dont want to mess with these cells - these are the tipper names, populated by a sheet formula
          ));
    }

    //try 5 times to submit all gsheet changes in one go
    int maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final batchUpdateRequest = BatchUpdateSpreadsheetRequest(requests: [
          Request(
              updateCells: UpdateCellsRequest(
                  fields: '*',
                  range: GridRange(
                    startColumnIndex: 2,
                    sheetId: appTipsSheet.id,
                    startRowIndex: 0,
                  ),
                  rows: rowDataList)),
        ]);
        await sheetsApi.spreadsheets
            .batchUpdate(batchUpdateRequest, spreadsheetId!);
        // break of the loop when the request is successful
        break;
      } catch (e) {
        log('Error ${e.toString()} submitting default tips, attempt $attempt of $maxAttempts');
        await Future.delayed(
            const Duration(seconds: 10)); // Wait for 60 seconds
      }
    }
  }

  Future<void> saveToGoogleSheets_NOT_USED(
      List<Map<String, dynamic>> rows) async {
    int maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await appTipsSheet.values.map.appendRows(rows);
        break; // If the request is successful, break out of the loop
      } catch (e) {
        log('Error ${e.toString()} submitting default tips for all tippers');

        await Future.delayed(const Duration(seconds: 5)); // Wait for 5 seconds
      }
    }
  }

  Future<void> submitTip(
      String tipperName, Tip tip, int gameIndex, int dauRoundNumber) async {
    await _initialLoadCompleter.future;
    log('Initial legacy gsheet load complete. submitTips()');

    // Find the row with the matching TipperName
    final rowToUpdate = appTipsData!.indexWhere((row) => row[0] == tipperName);

    if (rowToUpdate == -1) {
      // If a matching row is not found, throw exception
      throw Exception(
          'Tipper $tipperName cannot be found in the legacy tipping sheet AppTips tab');
    } else {
      // update existing row
      // 1) grab the existing cell data if any
      // 2) if tip league == League.NRL, starting at index 0, use the gameIndex to update the cell data at that position with the game result
      // 3) if tip league == League.AFL, starting at index 8, use the gameIndex to update the cell data at that position with the game result
      // 4) update the row with the new cell data

      var cellValue = await appTipsSheet.values
          .value(row: rowToUpdate + 1, column: dauRoundNumber + 2);

      if (cellValue.length != 17) {
        throw Exception(
            'Error updating legacy tipping sheet with tip $cellValue for $tipperName in game ${tip.game.dbkey}. Existing legacy tips length should be 17, but is ${cellValue.length}  ');
      }

      if (tip.game.league == League.nrl) {
        cellValue =
            cellValue.replaceRange(gameIndex, gameIndex + 1, tip.tip.name);
      } else {
        cellValue =
            cellValue.replaceRange(gameIndex + 8, gameIndex + 9, tip.tip.name);
      }

      appTipsSheet.values.insertValue(cellValue,
          row: rowToUpdate + 1, column: dauRoundNumber + 2);

      log('Updated legacy tipping sheet with tip $cellValue for $tipperName in game ${tip.game.dbkey}');

      //await sheet.values.insertRow(rowToUpdate + 1, [nrlTips + aflTips],
      //    fromColumn: dauRoundNumber + 2);
    }
  }
}
