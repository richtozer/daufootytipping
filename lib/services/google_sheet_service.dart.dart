import 'dart:async';
import 'dart:developer';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/dauround.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring_roundscores.dart';
import 'package:daufootytipping/models/tipgame.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/models/tipperrole.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/scoring_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/view_models/tips_viewmodel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/sheets/v4.dart' hide Spreadsheet;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:gsheets/gsheets.dart';
import 'package:watch_it/watch_it.dart';

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

  int numInsertedRows = 0;

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
  Future<List<Tipper>> getLegacyTippers() async {
    List<Tipper> tippers = [];

    await initialized();

    // get refreshed data from the gsheet
    // get the tippers data from the gsheet, skip header row
    tippersRows = (await tippersSheet.values.allRows()).skip(1).toList();
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
            //auto assign all new tippers created in sheet this year, to the current comp
            DAUComp(
                dbkey: di<DAUCompsViewModel>().selectedDAUComp!.dbkey,
                name:
                    'blah', //dummy data ok here, because this object is not saved anywhere, we just need it for the current comp key
                aflFixtureJsonURL: Uri.parse(
                    'https://www.google.com'), //dummy data ok here, because this object is not saved anywhere, we just need it for the current comp key
                nrlFixtureJsonURL: Uri.parse('https://www.google.com'),
                daurounds: []), // dummy data ok here, because this object is not saved anywhere,  we just need it for the current comp key
          ],
        );

        tippers.add(tipper);
      }
    }

    return tippers;
  }

//method to convert gsheet rows of apptips into a list of GsheetAppTip objects
  Future<List<GsheetAppTip>> getLegacyAppTips() async {
    List<GsheetAppTip> appTips = [];

    await initialized();

    // get refreshed data from the gsheet, skip header rows
    appTipsData = (await appTipsSheet.values.allRows()).skip(3).toList();
    numInsertedRows = appTipsData.length;

    log('Refresh of legacy gsheet ${appTipsSheet.title} complete. Found $numInsertedRows rows.');

    // sample data
    // FormSubmitTimestamp	DAU Round	Name	Round Tips
    // 2024-01-01 10:00:00	1	Ex Parrot	dddbbbddbabezzzzz
    // 2024-02-29 06:26:04	1	mad kiwi	bdbabbbdbbbbzzzzz

    for (var row in appTipsData) {
      if (row.length < 4) {
        log('Error in legacy tipping sheet: row has less than 4 columns of data. We need at least formSubmitTimestamp, dauRoundNumber, name, roundTipslegacyFormat : $row. skipping this row');
      } else {
        GsheetAppTip appTip = GsheetAppTip(
          row[0] ?? '',
          int.parse(row[1] ?? '0'),
          row[2] ?? '',
          row[3] ?? '',
        );

        appTips.add(appTip);
      }
    }

    return appTips;
  }

  Future<String> syncSingleTipToLegacy(
      TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      TipGame tipGame,
      DAURound dauRound) async {
    try {
      await initialized();

      String res = await _identifySyncChanges(
          allTipsViewModel, daucompsViewModel, [dauRound], tipGame.tipper);

      return res;
    } catch (e) {
      log('Error syncing single tip to legacy: $e');
      return 'Error syncing single tip to legacy: $e';
    }
  }

// method to sync tips to legacy tipping sheet
  Future<String> syncAllTipsToLegacy(TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel, Tipper? onlySyncThisTipper) async {
    try {
      await initialized();

      List<DAURound> combinedRounds =
          await daucompsViewModel.getCombinedRounds();

      String res = await _identifySyncChanges(allTipsViewModel,
          daucompsViewModel, combinedRounds, onlySyncThisTipper);

      return res;
    } catch (e) {
      log('Error syncing all tips to legacy: $e');
      return 'Error syncing all tips to legacy: $e';
    }
  }

  Future<String> _identifySyncChanges(
      TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      List<DAURound> syncTheseRounds,
      Tipper? onlySyncThisTipper) async {
    // List<String> templateDefaultTips =
    //     await _getDefaultTips(daucompsViewModel, combinedRounds);

    List<Tipper> tippers = [];
    if (onlySyncThisTipper != null) {
      tippers.add(onlySyncThisTipper);
    } else {
      tippers = await getLegacyTippers();
    }

    // for testing, filter tippers to find my record richard.tozer@gmail.com
    // tippers = tippers
    //     .where((element) => element.email == 'richard.tozer@gmail.com')
    //     .toList();

    //refresh app tips data
    await refreshAppTipsData();

    //keep track of the number of sync changes
    int syncChanges = 0;

    // loop through the supplied combined rounds and get the tips for each round
    for (DAURound syncThisRound in syncTheseRounds) {
      // get the default tips for this round
      String templateDefaultTips = await daucompsViewModel
          .getDefaultTipsForCombinedRoundNumber(syncThisRound);
      // for each tipper in the supplied list, get their tips for each round and create a GsheetAppTip object
      for (Tipper tipper in tippers) {
        bool res = await _syncChangesForRoundTipper(
            allTipsViewModel,
            daucompsViewModel,
            syncTheseRounds,
            tipper,
            syncThisRound,
            templateDefaultTips);
        if (res) {
          syncChanges++;
        }
      }
    }

    return 'Sync to legacy complete. Applied $syncChanges changes';
  }

  Future<bool> _syncChangesForRoundTipper(
      TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      List<DAURound> combinedRounds,
      Tipper tipper,
      DAURound round,
      String templateDefaultTips) async {
    DAUComp? daucomp = await daucompsViewModel.getCurrentDAUComp();

    GsheetAppTip? gsheetAppTip = await _getAppTipsForRoundTipper(
        allTipsViewModel, tipper, round, daucomp!, templateDefaultTips);
    // if gsheetAppTip is not null, then check appTipsSheet for this round/tipper combination
    // check GsheetAppTip.roundTipslegacyFormat against the appTipsSheet data
    // if they are different, then submit a gsheet update now
    if (gsheetAppTip != null) {
      // search List appTipsData for this round/tipper combination
      // if found, compare with roundTipslegacyFormat
      // if different, submit a gsheet update
      // if not found, submit a new row
      // ignore the first 3 rows as they are header rows

      for (var row in appTipsData.skip(3)) {
        if (row[1] == gsheetAppTip.dauRoundNumber.toString() &&
            row[2] == gsheetAppTip.name) {
          // found the row, now compare the roundTipslegacyFormat
          if (row[3] != gsheetAppTip.roundTipslegacyFormat) {
            // submit a gsheet update now
            log('*** Found a difference in round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}. Submitting update now');

            // write the updated tip back to the gsheet, this will also refresh the timestamp
            bool res = await appTipsSheet.values.insertRow(
                appTipsData.indexOf(row) + 1,
                [
                  gsheetAppTip.formSubmitTimestamp,
                  gsheetAppTip.dauRoundNumber,
                  gsheetAppTip.name,
                  gsheetAppTip.roundTipslegacyFormat
                ],
                fromColumn: 1);

            if (res) {
              log('*** Row updated for round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}.');
            } else {
              log('*** Error updating row for round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}.');
            }

            return res;
          } else {
            log('*** Found no difference in round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}. Skipping update');
            return false;
          }
        }
      }

      // if we get here, then we have not found the round/tipper combination in the appTipsSheet
      // this round/tipper combination does not exist in the appTipsSheet
      // so submit a new row
      log('*** Did not find round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}. Submitting new row now');
      // now insert a new row into the appTipsSheet
      numInsertedRows++;
      int nextNewRowNumber = numInsertedRows;
      bool res = await appTipsSheet.values.insertRow(
          nextNewRowNumber,
          [
            gsheetAppTip.formSubmitTimestamp,
            gsheetAppTip.dauRoundNumber,
            gsheetAppTip.name,
            gsheetAppTip.roundTipslegacyFormat,
            '=IF(MAXIFS(\$A:\$A,\$B:\$B,B$nextNewRowNumber,\$C:\$C,C$nextNewRowNumber)=A$nextNewRowNumber,TRUE,)',
            '=vlookup(B$nextNewRowNumber,DAURounds!\$A\$2:G,7,true)',
            '=LEN(D$nextNewRowNumber)-LEN(SUBSTITUTE(SUBSTITUTE(D$nextNewRowNumber,"a",""),"e",""))',
            '=ARRAYFORMULA(SUM(IF((MID(D$nextNewRowNumber,ROW(INDIRECT("1:"&LEN(D$nextNewRowNumber))),1) = MID(F$nextNewRowNumber,ROW(INDIRECT("1:"&LEN(F$nextNewRowNumber))),1)) * (MID(D$nextNewRowNumber,ROW(INDIRECT("1:"&LEN(D$nextNewRowNumber))),1) = {"a","e"}), 1, 0)))',
            '=VLOOKUP(mid(\$F$nextNewRowNumber,1,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,1,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,2,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,2,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,3,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,3,1), NRLScoreTipper, 0), FALSE) +VLOOKUP(mid(\$F$nextNewRowNumber,4,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,4,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,5,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,5,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,6,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,6,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,7,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,7,1), NRLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,8,1), NRLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,8,1), NRLScoreTipper, 0), FALSE)',
            '=VLOOKUP(mid(\$F$nextNewRowNumber,9,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,9,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,10,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,10,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,11,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,11,1), AFLScoreTipper, 0), FALSE) +VLOOKUP(mid(\$F$nextNewRowNumber,12,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,12,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,13,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,13,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,14,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,14,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,15,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,15,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,16,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,16,1), AFLScoreTipper, 0), FALSE) + VLOOKUP(mid(\$F$nextNewRowNumber,17,1), AFLScoreMatch, MATCH(mid(\$D$nextNewRowNumber,17,1), AFLScoreTipper, 0), FALSE)',
            '=I$nextNewRowNumber+J$nextNewRowNumber',
          ],
          fromColumn: 1);
      if (res) {
        log('*** New row added for round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}.');
      } else {
        log('*** Error adding new row for round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}.');
      }
      return res;
    }
    return false;
  }

  // Future<List<String>> _getDefaultTips(
  //     DAUCompsViewModel daucompsViewModel, List<int> combinedRounds) async {
  //   return await Future.wait(combinedRounds.map((roundNumber) async =>
  //       daucompsViewModel.getDefaultTipsForCombinedRoundNumber(roundNumber)));
  // }

  Future<GsheetAppTip?> _getAppTipsForRoundTipper(
      TipsViewModel allTipsViewModel,
      Tipper tipper,
      DAURound round,
      DAUComp daucomp,
      String templateDefaultTips) async {
    String roundTips = templateDefaultTips;

    List<TipGame?> tipGames =
        await allTipsViewModel.getTipsForRound(tipper, round, daucomp);

    // as we loop through the tips, check if tips any are from legacy, if they
    // *ALL* are then ignore them and drop this update by returning an empty string

    bool isAllLegacyTips = true;
    int appTipCount = 0;

    // keep track of the latest form submit timestamp for this round
    DateTime maxFormSubmitTimestamp = DateTime(1970);

    for (TipGame? tipGame in tipGames) {
      //DAURound dauround = tipGame!.game.getDAURound(daucomp);

      if (tipGame!.legacyTip == false) {
        isAllLegacyTips = false;
        appTipCount++;
        // is the submit time the latest for this round?
        if (tipGame.submittedTimeUTC.isAfter(maxFormSubmitTimestamp)) {
          maxFormSubmitTimestamp = tipGame.submittedTimeUTC;
        }
      }

      roundTips = _updateLegacyTipsString(roundTips, tipGame, round);
    }

    if (!isAllLegacyTips) {
      log('*** $appTipCount tips for ${tipper.name} in round ${round.dAUroundNumber} are from the app.');
      return GsheetAppTip(maxFormSubmitTimestamp.toLocal().toIso8601String(),
          round.dAUroundNumber, tipper.name, roundTips);
    } else {
      // this round/tipper combination did not have any app tips, so return null
      //log('All tips for ${tipper.name} in round $round are from the legacy system, so skipping this round/tipper combination for sync');
      return null;
    }
  }

  // BatchUpdateSpreadsheetRequest _addHeaderRowData(
  //     BatchUpdateSpreadsheetRequest differences, List<int> combinedRounds) {
  //   RowData headerRowData = RowData();

  //   // add cell data for these column headers: FormSubmitTimestamp	DAU Round	Name	Round Tips
  //   headerRowData.values = [
  //     CellData(
  //         userEnteredValue: ExtendedValue(stringValue: 'FormSubmitTimestamp')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'DAU Round')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Name')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Round Tips')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Latest Tip')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Round result')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Margin Picks')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Margin UPS')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'NRL Score')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'AFL Score')),
  //     CellData(userEnteredValue: ExtendedValue(stringValue: 'Total Score')),

  //     //Latest Tip	Round result	Margin Picks	Margin UPS	NRL Score	AFL Score	Total Score
  //   ];

  //   differences.requests!.add(Request(
  //       updateCells: UpdateCellsRequest(
  //           fields: '*',
  //           range: GridRange(
  //             sheetId: appTipsSheet.id,
  //             startRowIndex: 2,
  //             endRowIndex: 3,
  //             startColumnIndex: 0,
  //             endColumnIndex: headerRowData.values!.length + 2,
  //           ),
  //           rows: [headerRowData])));

  //   return differences;
  // }

  //function to update the default tipper data with the new tip. Use the league and matchnumber to find the correct character to update
  String _updateLegacyTipsString(
      String defaultRoundTips, TipGame tipGame, DAURound dauRound) {
    //figure out the offset to update based on the relative position of game in dauround.games list
    // that is the offset to use to update the proposedGsheetTipChanges
    int gameIndex = dauRound.games.indexOf(tipGame.game);

    // if the count of NRL games is less than 8, then we need to add the difference to
    // any gameIndex when the game is for AFL
    if (dauRound.games.where((game) => game.league == League.nrl).length < 8 &&
        tipGame.game.league == League.afl) {
      gameIndex +=
          8 - dauRound.games.where((game) => game.league == League.nrl).length;
    }

    // assert that gameindex is not -1
    assert(gameIndex != -1);

    defaultRoundTips = defaultRoundTips.replaceRange(
        gameIndex, gameIndex + 1, tipGame.tip.name);

    return defaultRoundTips;
  }

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

    numInsertedRows = appTipsData.length;

    log('Legacy sheet ${appTipsSheet.title} data loaded in app. Found $numInsertedRows rows.');
  }

// List<RoundScores> getTipperRoundScoresForComp(Tipper tipper)
  // Method to sync round scores to a dedicated sheet in the gsheet
  // All data will be refreshed with each sync.
  // Using the list of active tippers use List<RoundScores> getTipperRoundScoresForComp(Tipper tipper)
  // to grab data from ScoresViewModel.
  // Write the data to the sheet using this header:
  //  DAU Round,Name,Margin Picks,Margin UPS,NRL Score,AFL Score,Total Score

  Future<void> syncRoundScoresToLegacy() async {
    await initialized();

    // get the sheet to write to
    final Worksheet roundScoresSheet =
        spreadsheet.worksheetByTitle('AppScores')!;

    // get the current data from the sheet
    final List<List<String?>> roundScoresData =
        await roundScoresSheet.values.allRows();

    // clear the sheet
    await roundScoresSheet.clear();

    // keep track of number of inserted rows
    numInsertedRows = 0;

    // add the header row
    await roundScoresSheet.values.insertRow(
        1,
        [
          'DAU Round',
          'Name',
          'Margin Picks',
          'Margin UPS',
          'NRL Score',
          'AFL Score',
          'Total Score'
          // =QUERY(ValidTips2!$A$5:$J, "Select F Where B = " & $A2 & " AND C = '" & $B2 & "'")
          //=QUERY(ValidTips2!$A$5:$J, "Select F Where B = " & $A3 & " AND C = '" & $B3 & "'")
          //...
        ],
        fromColumn: 1);

    numInsertedRows++;

    //grab the active tippers from TippersViewModel
    List<Tipper> activeTippers = await di<TippersViewModel>()
        .getActiveTippers(di<DAUCompsViewModel>().selectedDAUComp!);

    // grab all the round scores from ScoresViewModel.allTipperRoundScores
    // the rounds are ordered in the list by index i.e round 1 is at index 0
    Map<Tipper, List<RoundScores>> roundScores =
        di<ScoresViewModel>().allTipperRoundScores;

    // call getHighestRoundNumberWithAllGamesPlayed to get the highest round number
    // with all games played
    int highestRoundNumber = di<DAUCompsViewModel>()
        .selectedDAUComp!
        .getHighestRoundNumberWithAllGamesPlayed();

    // Get the maximum length of tipperRoundScores
    int maxLen = activeTippers
        .map((tipper) => highestRoundNumber)
        .reduce((a, b) => a > b ? a : b);

    // Create a list to hold the rows
    List<List<Object>> rows = [];

    // Loop through the round scores
    for (int i = 0; i < maxLen; i++) {
      // Loop through the active tippers
      for (Tipper tipper in activeTippers) {
        List<RoundScores> tipperRoundScores = roundScores[tipper]!;
        // Check if the current index is within the length of the tipperRoundScores
        if (i < tipperRoundScores.length) {
          // Add the round score to the list of rows
          rows.add([
            i + 1,
            tipper.name,
            (tipperRoundScores[i].aflMarginTips +
                    tipperRoundScores[i].nrlMarginTips)
                .toString(),
            (tipperRoundScores[i].aflMarginUPS +
                    tipperRoundScores[i].nrlMarginUPS)
                .toString(),
            tipperRoundScores[i].nrlScore.toString(),
            tipperRoundScores[i].aflScore.toString(),
            (tipperRoundScores[i].nrlScore + tipperRoundScores[i].aflScore)
                .toString(),
            // compare with sheet scores by adding the queries for each column
            '=QUERY(ValidTips2!\$A\$5:\$J, "Select F Where B = " & \$A${numInsertedRows + 1} & " AND C = '
                " & \$B${numInsertedRows + 1} & "
                '")',
            '=QUERY(ValidTips2!\$A\$5:\$J, "Select G Where B = " & \$A${numInsertedRows + 1} & " AND C = '
                " & \$B${numInsertedRows + 1} & "
                '")',
            '=QUERY(ValidTips2!\$A\$5:\$J, "Select H Where B = " & \$A${numInsertedRows + 1} & " AND C = '
                " & \$B${numInsertedRows + 1} & "
                '")',
            '=QUERY(ValidTips2!\$A\$5:\$J, "Select I Where B = " & \$A${numInsertedRows + 1} & " AND C = '
                " & \$B${numInsertedRows + 1} & "
                '")',
            '=QUERY(ValidTips2!\$A\$5:\$J, "Select J Where B = " & \$A${numInsertedRows + 1} & " AND C = '
                " & \$B${numInsertedRows + 1} & "
                '")',
          ]);
        }
      }
    }

    // Write all the rows to the sheet at once
    await roundScoresSheet.values.appendRows(rows, fromColumn: 1);
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
