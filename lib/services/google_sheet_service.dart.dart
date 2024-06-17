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

  final Map<DAURound, CallCoalescer> coalescers = {};

  // Call this method to await the initial load of the gsheet
  Future<void> initialized() => _initialLoadCompleter.future;

  LegacyTippingService() {
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

      log('Using Gsheet sheet with id $spreadsheetId');

      spreadsheet = await gsheets.spreadsheet(spreadsheetId!);
      appTipsSheet = spreadsheet.worksheetByTitle(appTipsSheetName)!;
      tippersSheet = spreadsheet.worksheetByTitle(tippersSheetName)!;

      tippersRows = await tippersSheet.values.allRows();
      log('Initial legacy gsheet load of sheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

      _refreshAppTipsData();
    } catch (e) {
      log('Error initializing legacy tipping service: ${e.toString()}');
    } finally {
      _initialLoadCompleter.complete();
    }
  }

  // Retrieves legacy tippers from the legacy gsheet and constructs Tipper objects based on the data retrieved.
  Future<List<Tipper>> getLegacyTippers() async {
    List<Tipper> tippers = [];

    await initialized();

    tippersRows = (await tippersSheet.values.allRows()).skip(1).toList();
    log('Refresh of legacy gsheet ${tippersSheet.title} complete. Found ${tippersRows.length} rows.');

    for (var row in tippersRows) {
      if (row.length < 4) {
        log('Error in legacy tipping sheet: row has less than 5 columns of data. We need at least name, email, type e.g. form and tipperID : $row. skipping this row');
      } else {
        Tipper tipper = Tipper(
          authuid: row[1].toLowerCase(),
          email: row[1].toLowerCase(),
          name: row[0],
          tipperID: row[4],
          tipperRole: row[2] == 'Admin' ? TipperRole.admin : TipperRole.tipper,
          compsParticipatedIn: [
            DAUComp(
              dbkey: di<DAUCompsViewModel>().selectedDAUComp!.dbkey,
              name: 'blah',
              aflFixtureJsonURL: Uri.parse('https://www.google.com'),
              nrlFixtureJsonURL: Uri.parse('https://www.google.com'),
              daurounds: [],
            ),
          ],
        );

        tippers.add(tipper);
      }
    }

    return tippers;
  }

  // Future<List<GsheetAppTip>> _getLegacyAppTips() async {
  //   List<GsheetAppTip> appTips = [];

  //   await initialized();

  //   appTipsData = (await appTipsSheet.values.allRows()).skip(3).toList();
  //   numInsertedRows = appTipsData.length;

  //   log('Refresh of legacy gsheet ${appTipsSheet.title} complete. Found $numInsertedRows rows.');

  //   for (var row in appTipsData) {
  //     if (row.length < 4) {
  //       log('Error in legacy tipping sheet: row has less than 4 columns of data. We need at least formSubmitTimestamp, dauRoundNumber, name, roundTipslegacyFormat : $row. skipping this row');
  //     } else {
  //       GsheetAppTip appTip = GsheetAppTip(
  //         row[0] ?? '',
  //         int.parse(row[1] ?? '0'),
  //         row[2] ?? '',
  //         row[3] ?? '',
  //       );

  //       appTips.add(appTip);
  //     }
  //   }

  //   return appTips;
  // }

  Future<String> syncSingleRoundTipperToLegacy(
      TipsViewModel allTipsViewModel,
      DAUCompsViewModel daucompsViewModel,
      TipGame tipGame,
      DAURound dauRound) async {
    try {
      await initialized();

      // use a call coalescer to releave pressure on the gsheet. If a call is made within 10 seconds of the last call, it will be coalesced into the same call
      coalescers[dauRound] ??= CallCoalescer(
        delay: const Duration(seconds: 10),
        onTimeout: () async {
          String res = await _identifySyncChanges(
              allTipsViewModel, daucompsViewModel, [dauRound], tipGame.tipper);
          return res;
        },
      );

      log('Syncing single tip to legacy for ${tipGame.tipper.name} in round ${dauRound.dAUroundNumber}');

      log(await coalescers[dauRound]!.call());
      return 'Sync scheduled';
    } catch (e) {
      log('Error syncing single tip to legacy: $e');
      return 'Error syncing single tip to legacy: $e';
    }
  }

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
    List<Tipper> tippers = [];
    if (onlySyncThisTipper != null) {
      tippers.add(onlySyncThisTipper);
    } else {
      tippers = await getLegacyTippers();
    }

    await _refreshAppTipsData();

    int syncChanges = 0;

    for (DAURound syncThisRound in syncTheseRounds) {
      String templateDefaultTips = await daucompsViewModel
          .getDefaultTipsForCombinedRoundNumber(syncThisRound);
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
    if (gsheetAppTip != null) {
      for (var row in appTipsData.skip(3)) {
        if (row[1] == gsheetAppTip.dauRoundNumber.toString() &&
            row[2] == gsheetAppTip.name) {
          if (row[3] != gsheetAppTip.roundTipslegacyFormat) {
            log('*** Found a difference in round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}. Submitting update now');

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

      log('*** Did not find round ${gsheetAppTip.dauRoundNumber} for tipper ${gsheetAppTip.name}. Submitting new row now');
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

  Future<GsheetAppTip?> _getAppTipsForRoundTipper(
      TipsViewModel allTipsViewModel,
      Tipper tipper,
      DAURound round,
      DAUComp daucomp,
      String templateDefaultTips) async {
    String roundTips = templateDefaultTips;

    List<TipGame?> tipGames =
        await allTipsViewModel.getTipsForRound(tipper, round, daucomp);

    bool isAllLegacyTips = true;
    int appTipCount = 0;

    DateTime maxFormSubmitTimestamp = DateTime(1970);

    for (TipGame? tipGame in tipGames) {
      if (tipGame!.legacyTip == false) {
        isAllLegacyTips = false;
        appTipCount++;
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
      return null;
    }
  }

  String _updateLegacyTipsString(
      String defaultRoundTips, TipGame tipGame, DAURound dauRound) {
    int gameIndex = dauRound.games.indexOf(tipGame.game);

    if (dauRound.games.where((game) => game.league == League.nrl).length < 8 &&
        tipGame.game.league == League.afl) {
      gameIndex +=
          8 - dauRound.games.where((game) => game.league == League.nrl).length;
    }

    assert(gameIndex != -1);

    defaultRoundTips = defaultRoundTips.replaceRange(
        gameIndex, gameIndex + 1, tipGame.tip.name);

    return defaultRoundTips;
  }

  Future<void> _refreshAppTipsData() async {
    await initialized();

    final values = await sheetsApi.spreadsheets.values.get(
      spreadsheetId!,
      appTipsSheetName,
    );

    appTipsData = values.values
            ?.map((row) => row.map((e) => e.toString()).toList())
            .toList() ??
        [];

    numInsertedRows = appTipsData.length;

    log('Legacy sheet ${appTipsSheet.title} data loaded in app. Found $numInsertedRows rows.');
  }

  Future<void> syncRoundScoresToLegacy() async {
    await initialized();

    final Worksheet roundScoresSheet =
        spreadsheet.worksheetByTitle('AppScores')!;

    final List<List<String?>> roundScoresData =
        await roundScoresSheet.values.allRows();

    await roundScoresSheet.clear();

    numInsertedRows = 0;

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
        ],
        fromColumn: 1);

    numInsertedRows++;

    List<Tipper> activeTippers = await di<TippersViewModel>()
        .getActiveTippers(di<DAUCompsViewModel>().selectedDAUComp!);

    Map<Tipper, List<RoundScores>> roundScores =
        di<ScoresViewModel>().allTipperRoundScores;

    int highestRoundNumber = di<DAUCompsViewModel>()
        .selectedDAUComp!
        .getHighestRoundNumberWithAllGamesPlayed();

    int maxLen = activeTippers
        .map((tipper) => highestRoundNumber)
        .reduce((a, b) => a > b ? a : b);

    List<List<Object>> rows = [];

    for (int i = 0; i < maxLen; i++) {
      for (Tipper tipper in activeTippers) {
        List<RoundScores> tipperRoundScores = roundScores[tipper]!;
        if (i < tipperRoundScores.length) {
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
          ]);
        }
      }
    }

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

/// A class that helps coalesce multiple calls into a single call.
class CallCoalescer {
  Timer? _timer;
  bool _isTimerActive = false;
  final Duration _delay;
  final Future<String> Function() _onTimeout;
  Completer<String>? _completer;

  CallCoalescer(
      {required Duration delay, required Future<String> Function() onTimeout})
      : _delay = delay,
        _onTimeout = onTimeout;

  Future<String> call() {
    if (_isTimerActive) {
      _resetTimer();
      return Future.value('The call has been coalesced with another call');
    } else {
      _startTimer();
      _completer = Completer<String>();
      return _completer!.future;
    }
  }

  void _startTimer() {
    _isTimerActive = true;
    _timer = Timer(_delay, _handleTimeout);
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(_delay, _handleTimeout);
  }

  Future<void> _handleTimeout() async {
    _isTimerActive = false;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(await _onTimeout());
    }
  }
}
