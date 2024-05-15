import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
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
  late List<List<String?>> appTipsData;

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
    try {
      AutoRefreshingAuthClient client = await gsheets.client;
      sheetsApi = SheetsApi(client);

      log('Using Gsheet shseet with id $spreadsheetId');

      spreadsheet = await gsheets.spreadsheet(spreadsheetId!);
      appTipsSheet = spreadsheet.worksheetByTitle(appTipsSheetName)!;
      tippersSheet = spreadsheet.worksheetByTitle(tippersSheetName)!;

      tippersRows = await tippersSheet.values.allRows();
      log('Initial legacy gsheet load of sheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

      refreshAppTipsData();
    } catch (e) {
      log('Error initialising legacy tipping service: ${e.toString()}');
    } finally {
      _initialLoadCompleter.complete();
    }
  }

  //method to convert gsheet rows of tippers into a list of Tipper objects
  Future<List<Tipper>> getLegacyTippers(DAUComp currentComp) async {
    List<Tipper> tippers = [];

    await initialized();

    // get refreshed data from the gsheet
    tippersRows = await tippersSheet.values.allRows();
    log('Refresh of legacy gsheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

    for (var row in tippersRows) {
      if (row.length < 4) {
        log('Error in legacy tipping sheet: row has less than 5 columns of data. We need at least name, email, type e.g. form and tipperID : $row. skipping this row');
      } else {
        Tipper tipper = Tipper(
          authuid: row[1].toLowerCase(),
          email: row[1]
              .toLowerCase(), // make sure we store the email in lowercase, for later consitent searching
          name: row[0],
          tipperID: row[
              4], //this is the primary key to support lecacy tipping service
          tipperRole: row[2] == 'Admin' ? TipperRole.admin : TipperRole.tipper,
          compsParticipatedIn: [
            //auto assign all new tippers created in sheet this year to the current comp
            currentComp,
          ],
        );

        tippers.add(tipper);
      }
    }

    return tippers;
  }

  Future<String> syncTipsToLegacy(TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel) async {
    await initialized();

    List<int> combinedRounds =
        await daucompsViewModel.getCombinedRoundNumbers();

    List<GsheetAppTip> proposedGsheetTipChanges = await _createProposedChanges(
        allTipsViewModel, daucompsViewModel, combinedRounds);

    // batch up proposedGsheetTipChanges into a single request
    BatchUpdateSpreadsheetRequest updates = BatchUpdateSpreadsheetRequest();
    updates.requests = [];

    int rowToUpdate = 1;

    //_TypeError (type 'Null' is not a subtype of type 'GsheetAppTip' in type cast)

    for (GsheetAppTip proposedGsheetTipChange in proposedGsheetTipChanges) {
      // update existing row
      // 1) grab the existing cell data if any
      // 2) update the row with the new cell data

      int offsetRowToUpdate = rowToUpdate + 3;
      appTipsSheet.values.insertRow(
          offsetRowToUpdate,
          [
            proposedGsheetTipChange.formSubmitTimestamp,
            proposedGsheetTipChange.dauRoundNumber,
            proposedGsheetTipChange.name,
            proposedGsheetTipChange.roundTipslegacyFormat,
            '=IF(MAXIFS(\$A:\$A,\$B:\$B,B$offsetRowToUpdate,\$C:\$C,C$offsetRowToUpdate)=A$offsetRowToUpdate,TRUE,)',
            '=vlookup(B$offsetRowToUpdate,DAURounds!\$A\$2:G,7,true)',
            '=LEN(D$offsetRowToUpdate)-LEN(SUBSTITUTE(SUBSTITUTE(D$offsetRowToUpdate,"a",""),"e",""))',
            '=ARRAYFORMULA(SUM(IF((MID(D$offsetRowToUpdate,ROW(INDIRECT("1:"&LEN(D$offsetRowToUpdate))),1) = MID(F$offsetRowToUpdate,ROW(INDIRECT("1:"&LEN(F$offsetRowToUpdate))),1)) * (MID(D$offsetRowToUpdate,ROW(INDIRECT("1:"&LEN(D$offsetRowToUpdate))),1) = {"a","e"}), 1, 0)))',
            '=VLOOKUP(mid(\$F$offsetRowToUpdate,1,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,1,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,2,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,2,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,3,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,3,1), NRLScoreTipper, 0), FALSE) +VLOOKUP(mid(\$F$offsetRowToUpdate,4,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,4,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,5,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,5,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,6,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,6,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,7,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,7,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,8,1), NRLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,8,1), NRLScoreTipper, 0), FALSE)',
            '=VLOOKUP(mid(\$F$offsetRowToUpdate,9,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,9,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,10,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,10,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,11,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,11,1), AFLScoreTipper, 0), FALSE) +VLOOKUP(mid(\$F$offsetRowToUpdate,12,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,12,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,13,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,13,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,14,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,14,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,15,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,15,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$offsetRowToUpdate,16,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,16,1), AFLScoreTipper, 0), FALSE)  + VLOOKUP(mid(\$F$offsetRowToUpdate,17,1), AFLScoreMatch, MATCH(mid(\$D$offsetRowToUpdate,17,1), AFLScoreTipper, 0), FALSE)',
            '=I$offsetRowToUpdate+J$offsetRowToUpdate'
          ],
          fromColumn: 1);

      rowToUpdate++;
    }

    updates = _addHeaderRowData(updates, combinedRounds);

    return await _submitChanges(updates);
  }

  Future<List<GsheetAppTip>> _createProposedChanges(
      TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      List<int> combinedRounds) async {
    List<String> templateDefaultTips =
        await _getDefaultTips(daucompsViewModel, combinedRounds);

    DAUComp? currentComp = daucompsViewModel.selectedDAUComp;

    List<Tipper> tippers = await getLegacyTippers(currentComp!);

    // for each tipper, get their tips for each round and create a GsheetAppTip object
    // for each round/tipper combination
    List<GsheetAppTip> proposedGsheetTipChanges = [];

    // loop through legacy tippers - skip header row
    for (Tipper tipper in tippers.skip(1)) {
      // loop through the combined rounds and get the tips for each round
      for (int round in combinedRounds) {
        proposedGsheetTipChanges = await _getAppTipsForRound(allTipsViewModel,
            tipper, round, templateDefaultTips, proposedGsheetTipChanges);
      }
    }
    return proposedGsheetTipChanges;
  }

  Future<List<String>> _getDefaultTips(
      DAUCompsViewModel daucompsViewModel, List<int> combinedRounds) async {
    return await Future.wait(combinedRounds.map((roundNumber) async =>
        daucompsViewModel.getDefaultTipsForCombinedRoundNumber(roundNumber)));
  }

  Future<List<GsheetAppTip>> _getAppTipsForRound(
      TipsViewModel allTipsViewModel,
      Tipper tipper,
      int round,
      List<String> templateDefaultTips,
      List<GsheetAppTip> proposedGsheetTipChanges) async {
    String roundTips = templateDefaultTips[round - 1];

    List<TipGame?> tipGames =
        await allTipsViewModel.getTipsForRound(tipper, round);

    // as we loop through the tips, check if tips are from legacy, if they
    // *all* are then ignore them and drop this update by returning an empty string

    bool isAllLegacyTips = true;

    // keep track of the latest form submit timestamp for this round
    DateTime maxFormSubmitTimestamp = DateTime(1970);

    for (TipGame? tipGame in tipGames) {
      if (tipGame!.legacyTip == false) {
        isAllLegacyTips = false;
        // is the submit time the latest for this round?
        if (tipGame.submittedTimeUTC.isAfter(maxFormSubmitTimestamp)) {
          maxFormSubmitTimestamp = tipGame.submittedTimeUTC;
        }
        roundTips = _updateDefaultTipperData(roundTips, tipGame);
      }
      roundTips = _updateDefaultTipperData(roundTips, tipGame);
    }

    if (!isAllLegacyTips) {
      log('*** Some tips for ${tipper.name} in round $round are from the app, so syncing changes');
      proposedGsheetTipChanges.add(GsheetAppTip(
          maxFormSubmitTimestamp.toLocal().toIso8601String(),
          round,
          tipper.name,
          roundTips));
    }

    return proposedGsheetTipChanges;
  }

  BatchUpdateSpreadsheetRequest _addHeaderRowData(
      BatchUpdateSpreadsheetRequest differences, List<int> combinedRounds) {
    RowData headerRowData = RowData();

    // add cell data for these column headers: FormSubmitTimestamp	DAU Round	Name	Round Tips
    headerRowData.values = [
      CellData(
          userEnteredValue: ExtendedValue(stringValue: 'FormSubmitTimestamp')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'DAU Round')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Name')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Round Tips')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Latest Tip')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Round result')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Margin Picks')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Margin UPS')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'NRL Score')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'AFL Score')),
      CellData(userEnteredValue: ExtendedValue(stringValue: 'Total Score')),

      //Latest Tip	Round result	Margin Picks	Margin UPS	NRL Score	AFL Score	Total Score
    ];

    differences.requests!.add(Request(
        updateCells: UpdateCellsRequest(
            fields: '*',
            range: GridRange(
              sheetId: appTipsSheet.id,
              startRowIndex: 2,
              endRowIndex: 3,
              startColumnIndex: 0,
              endColumnIndex: headerRowData.values!.length + 2,
            ),
            rows: [headerRowData])));

    return differences;
  }

  Future<String> _submitChanges(
      BatchUpdateSpreadsheetRequest differences) async {
    const int maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await sheetsApi.spreadsheets.batchUpdate(differences, spreadsheetId!);
        String msg =
            'Successfully made ${differences.requests!.length - 1} updates to legacy tipping sheet.';
        log(msg);
        return msg;
      } catch (e) {
        log('Error ${e.toString()} submitting default tips, attempt $attempt of $maxAttempts');
        await Future.delayed(const Duration(seconds: 10));
      }
    }
    return 'Failed to sync ${differences.requests!.length - 1}  tips to legacy tipping sheet after $maxAttempts attempts';
  }

  //function to update the default tipper data with the new tip. Use the league and matchnumber to find the correct character to update
  String _updateDefaultTipperData(String defaultRoundTips, TipGame tipGame) {
    if (tipGame.game.league == League.nrl) {
      //figure out the offset to update based on the relative position of game in dauround.games list
      // that is the offset to use to update the proposedGsheetTipChanges
      int gameIndex = tipGame.game.dauRound.games.indexOf(tipGame.game);

      defaultRoundTips = defaultRoundTips.replaceRange(
          gameIndex, gameIndex + 1, tipGame.tip.name);
    } else {
      //figure out the offset to update based on the relative position of game in dauround.games list
      // that is the offset to use to update the proposedGsheetTipChanges
      // add 8 to the offset to account for the fact that nrl tips go first in the string
      int gameIndex = 8 + tipGame.game.dauRound.games.indexOf(tipGame.game);

      defaultRoundTips = defaultRoundTips.replaceRange(
          gameIndex, gameIndex + 1, tipGame.tip.name);
    }

    return defaultRoundTips;
  }

  // Future<void> submitTip(
  //     String tipperName, TipGame tip, int gameIndex, int dauRoundNumber) async {
  //   // Find the row with the matching TipperName
  //   final rowToUpdate = appTipsData.indexWhere((row) => row[0] == tipperName);

  //   if (rowToUpdate == -1) {
  //     // If a matching row is not found, throw exception
  //     throw Exception(
  //         'Tipper $tipperName cannot be found in the legacy tipping sheet AppTips tab');
  //   } else {
  //     // update existing row
  //     // 1) grab the existing cell data if any
  //     // 2) if tip league == League.NRL, starting at index 0, use the gameIndex to update the cell data at that position with the game result
  //     // 3) if tip league == League.AFL, starting at index 8, use the gameIndex to update the cell data at that position with the game result
  //     // 4) update the row with the new cell data

  //     String cellValue = await appTipsSheet.values
  //         .value(row: rowToUpdate + 1, column: dauRoundNumber + 2);

  //     String newCellValue;

  //     if (cellValue.length != 17) {
  //       String msg =
  //           'Error updating legacy tipping sheet with tip $cellValue for $tipperName in game ${tip.game.dbkey}. Existing legacy tips length should be 17, but is ${cellValue.length}';
  //       log(msg);
  //       throw Exception(msg);
  //     }

  //     if (tip.game.league == League.nrl) {
  //       newCellValue =
  //           cellValue.replaceRange(gameIndex, gameIndex + 1, tip.tip.name);
  //     } else {
  //       newCellValue =
  //           cellValue.replaceRange(gameIndex + 8, gameIndex + 9, tip.tip.name);
  //     }

  //     appTipsSheet.values.insertValue(newCellValue,
  //         row: rowToUpdate + 1, column: dauRoundNumber + 2);

  //     log('Updated legacy tipping round: $dauRoundNumber for $tipperName. Old tips: $cellValue, new tips: $newCellValue. Tip change was for game: ${tip.game.dbkey}');

  //     await appTipsSheet.values.insertRow(rowToUpdate + 1, [newCellValue],
  //         fromColumn: dauRoundNumber + 2);
  //   }
  // }

  Future<void> refreshAppTipsData() async {
    await initialized();

    final values = await sheetsApi.spreadsheets.values.get(
      spreadsheetId!,
      appTipsSheetName,
    );

    // convert the values to a list of lists if values.values is not null
    appTipsData = values.values
            ?.map((row) => row.map((e) => e.toString()).toList())
            .toList() ??
        [];

    log('Legacy sheet ${appTipsSheet.title} data loaded in app. Found ${appTipsData.length} rows.');
  }
}

class GsheetAppTip {
  String formSubmitTimestamp;
  int dauRoundNumber;
  String name;
  String roundTipslegacyFormat;

  GsheetAppTip(this.formSubmitTimestamp, this.dauRoundNumber, this.name,
      this.roundTipslegacyFormat);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is GsheetAppTip &&
        other.formSubmitTimestamp == formSubmitTimestamp &&
        other.dauRoundNumber == dauRoundNumber &&
        other.name == name &&
        other.roundTipslegacyFormat == roundTipslegacyFormat;
  }

  @override
  int get hashCode {
    return formSubmitTimestamp.hashCode ^
        dauRoundNumber.hashCode ^
        name.hashCode ^
        roundTipslegacyFormat.hashCode;
  }
}
