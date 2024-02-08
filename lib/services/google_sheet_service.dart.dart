import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tip.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_tips_viewmodel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/sheets/v4.dart' hide Spreadsheet;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:gsheets/gsheets.dart';

/* 
https://itnext.io/dart-working-with-google-sheets-793ed322daa0
*/

class LegacyTippingService {
  late final GSheets gsheets;
  final String? spreadsheetId = dotenv.env['DAU_GSHEET_ID'];
  late final SheetsApi sheetsApi;
  late final Spreadsheet spreadsheet;

  late final Worksheet appTipsSheet;
  final String appTipsSheetName = 'AppTips';
  late final List<List<String?>> appTipsData;

  late final Worksheet tippersSheet;
  final String tippersSheetName = 'Tippers';
  late List<List<String>> tippersRows;

  final Completer<void> _initialLoadCompleter = Completer();

  // call this method to await the initial load of the gsheet
  Future<void> initialized() => _initialLoadCompleter.future;

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
    AutoRefreshingAuthClient client = await gsheets.client;
    sheetsApi = SheetsApi(client);

    spreadsheet = await gsheets.spreadsheet(spreadsheetId!);
    appTipsSheet = spreadsheet.worksheetByTitle(appTipsSheetName)!;
    tippersSheet = spreadsheet.worksheetByTitle(tippersSheetName)!;

    tippersRows = await tippersSheet.values.allRows();
    log('Initial legacy gsheet load of sheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

    final values = await sheetsApi.spreadsheets.values.get(
      spreadsheetId!,
      appTipsSheetName,
    );
    appTipsData = values.values!
        .map((list) => list.map((item) => item as String?).toList())
        .toList();

    log('Sheet ${appTipsSheet.title} data synced. Found ${appTipsData.length} rows.');

    _initialLoadCompleter.complete();
  }

  //method to convert gsheet rows of tippers into a list of Tipper objects
  Future<List<Tipper>> getLegacyTippers() async {
    List<Tipper> tippers = [];

    await spreadsheet.refresh();

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

//   Sync realtime databse tips to legacy gsheet
// - 1 Create a temporary 2 dimensional list (List<List<Object?>>) of proposed gsheet tip changes  - tipper is on the y dimension, daurounds is on the x dimension
//     - Populate with default tips for each tipper
//     - Loop through each DAURound
//         - 1 Get all current tips from realtime database using AllTipsViewModel.getTipsForRound()
//         - [ ] Update 2 dimensional list with any tips found.
// - 2 Now grab the current tips from gsheet alltips sheet, LegacyTippingService.appTipsData
// - 3 Compare the temporary list with the with proposed changes in appTipsData
// - 4 Any differences - batch up and apply to sheet so that it matches the temporary data

  Future<String> syncTipsToLegacyDiffOnly(
      AllTipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      GamesViewModel gamesViewModel) async {
    //refresh the data from the gsheet

    await spreadsheet.refresh(); //TODO is this a good idea, is it inefficient?

    //get the total number of combined rounds
    List<int> combinedRounds =
        await daucompsViewModel.getCombinedRoundNumbers();

    //Create a temporary 2 dimensional list (List<List<Object?>>) of proposed gsheet tip changes  - tipper is on the y dimension, daurounds is on the x dimension
    List<List<String?>> proposedGsheetTipChanges = [];

    //get a standard list of default tips for all tippers
    // loop through the combinedRounds from the GamesViewmodel starting at the current combined round and create default tips

    List<String> templateDefaultTips = [];
    for (int roundNumber in combinedRounds) {
      String defaultTips = await gamesViewModel
          .getDefaultTipsForCombinedRoundNumber(roundNumber);
      templateDefaultTips.add(defaultTips);
    }

    // Populate with default tips for each tipper
    List<Tipper> tippers = await getLegacyTippers();
    // get the length of tipper list and create a for loop
    // index 0 (row 1) has the header, lets igmore that
    for (int i = 1; i < tippers.length; i++) {
      //make sure we take a copy of the template, rather than a reference
      proposedGsheetTipChanges.add(List<String>.from(templateDefaultTips));
    }

    // Get all current tips from realtime database
    List<Tip> allTips = await allTipsViewModel.getTips();

    // Update 2 dimensional list with any tips found.
    for (Tip tip in allTips) {
      // Find the sheet index for the tipper tip.tipper.name
      int rowToUpdate =
          tippers.indexWhere((tipper) => tipper.name == tip.tipper.name);

      if (rowToUpdate == -1) {
        // If a matching row is not found, throw exception
        throw Exception(
            'Tipper ${tip.tipper.name} cannot be found in the legacy tipping sheet AppTips tab');
      } else {
        rowToUpdate--; //account for the removed header row

        // update the proposed tipper data with the new tip. Use the league and matchnumber to find the correct character to update
        var targetString = proposedGsheetTipChanges[rowToUpdate]
            [tip.game.combinedRoundNumber - 1];
        if (tip.game.league == League.nrl) {
          targetString = targetString?.replaceRange(
              tip.game.matchNumber - 1, tip.game.matchNumber, tip.tip.name);
          proposedGsheetTipChanges[rowToUpdate]
              [tip.game.combinedRoundNumber - 1] = targetString;
        } else {
          targetString = targetString?.replaceRange(
              tip.game.matchNumber + 7, tip.game.matchNumber + 8, tip.tip.name);
          proposedGsheetTipChanges[rowToUpdate]
              [tip.game.combinedRoundNumber - 1] = targetString;
        }
      }
    }

    //ignore the first 2 columns of data in appTipsData as they have the tipper name and email
    List<List<String?>> currentSheetTipData = appTipsData.map((e) {
      return e.sublist(2);
    }).toList();

    //also ignore the first row of data in appTipsData as it has the header
    currentSheetTipData.removeAt(0);

    // compare proposedGsheetTipChanges with appTipsData and apply any differences
    // batch up any deifferences and apply to sheet so that it matches the temporary data
    BatchUpdateSpreadsheetRequest differences = compareForBatchUpdate(
        currentSheetTipData, proposedGsheetTipChanges, appTipsSheet.id);

    // update the header row - from column C, interate through the combinedRounds
    //and update the header row with the combined round number
    RowData headerRowData = RowData();
    headerRowData.values = [];
    for (int i = 2; i < combinedRounds.length + 2; i++) {
      headerRowData.values!.add(CellData(
          userEnteredValue: ExtendedValue(stringValue: 'Round ${i - 1}')));
    }

    //add the head row data to the batch update request
    differences.requests!.add(Request(
        updateCells: UpdateCellsRequest(
            fields: '*',
            range: GridRange(
              sheetId: appTipsSheet.id,
              startRowIndex: 0,
              endRowIndex: 1,
              startColumnIndex: 2,
              endColumnIndex: headerRowData.values!.length + 2,
            ),
            rows: [headerRowData])));

    //try 5 times to submit all gsheet changes in one go
    int maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await sheetsApi.spreadsheets.batchUpdate(differences, spreadsheetId!);
        // break of the loop when the request is successful
        String msg =
            'Successfully synced ${differences.requests!.length - 1} tips to legacy tipping sheet.';
        log(msg);
        return msg;
      } catch (e) {
        log('Error ${e.toString()} submitting default tips, attempt $attempt of $maxAttempts');
        await Future.delayed(
            const Duration(seconds: 10)); // Wait for 60 seconds
      }
    }
    return 'Failed to sync ${differences.requests!.length - 1}  tips to legacy tipping sheet after $maxAttempts attempts';
  }

  BatchUpdateSpreadsheetRequest compareForBatchUpdate(
      List<List<String?>> originalList,
      List<List<String?>> proposedList,
      int sheetId) {
    List<Request> requests = [];

    for (int i = 0; i < proposedList.length; i++) {
      for (int j = 0; j < proposedList[i].length; j++) {
        // if the original tip is empty or different to the proposed tip, then add a request to update the cell
        if (originalList[i].isEmpty ||
            originalList[i][j] != proposedList[i][j]) {
          requests.add(
            Request()
              ..updateCells = (UpdateCellsRequest()
                ..rows = [
                  RowData()
                    ..values = [
                      CellData()
                        ..userEnteredValue =
                            (ExtendedValue()..stringValue = proposedList[i][j])
                    ]
                ]
                ..range = (GridRange()
                  ..sheetId = sheetId
                  ..startRowIndex = i + 1 // add 1 to account for the header row
                  ..endRowIndex = i + 2
                  ..startColumnIndex =
                      j + 2 // add 2 to account for the name and email columns
                  ..endColumnIndex = j + 3)
                ..fields = 'userEnteredValue'),
          );
        }
      }
    }

    log('Syncing ${requests.length} tip changes to legacy tipping sheet.');

    return BatchUpdateSpreadsheetRequest()..requests = requests;
  }

  Future<void> submitTip(
      String tipperName, Tip tip, int gameIndex, int dauRoundNumber) async {
    // Find the row with the matching TipperName
    final rowToUpdate = appTipsData.indexWhere((row) => row[0] == tipperName);

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

      String cellValue = await appTipsSheet.values
          .value(row: rowToUpdate + 1, column: dauRoundNumber + 2);

      String newCellValue;

      if (cellValue.length != 17) {
        String msg =
            'Error updating legacy tipping sheet with tip $cellValue for $tipperName in game ${tip.game.dbkey}. Existing legacy tips length should be 17, but is ${cellValue.length}';
        log(msg);
        throw Exception(msg);
      }

      if (tip.game.league == League.nrl) {
        newCellValue =
            cellValue.replaceRange(gameIndex, gameIndex + 1, tip.tip.name);
      } else {
        newCellValue =
            cellValue.replaceRange(gameIndex + 8, gameIndex + 9, tip.tip.name);
      }

      appTipsSheet.values.insertValue(newCellValue,
          row: rowToUpdate + 1, column: dauRoundNumber + 2);

      log('Updated legacy tipping round: $dauRoundNumber for $tipperName. Old tips: $cellValue, new tips: $newCellValue. Tip change was for game: ${tip.game.dbkey}');

      await appTipsSheet.values.insertRow(rowToUpdate + 1, [newCellValue],
          fromColumn: dauRoundNumber + 2);
    }
  }
}
