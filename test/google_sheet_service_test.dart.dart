import 'package:daufootytipping/firebase_options.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LegacyTippingService', () {
    late LegacyTippingService tippingService;

    setUp(() async {
      await dotenv.load(); // Loads .env file
      await Firebase.initializeApp(
          options:
              DefaultFirebaseOptions.currentPlatform); // Initialize Firebase
      tippingService = LegacyTippingService();
    });

    // test('Initialized should complete successfully', () async {
    //   await tippingService.initialized();
    //   expect(true, true); // Placeholder assertion
    // });

    // test('getLegacyTippers should return a list of Tipper objects', () async {
    //   final tippers = await tippingService.getLegacyTippers();
    //   expect(tippers, isA<List<Tipper>>());
    // });

    // test('getLegacyAppTips should return a list of GsheetAppTip objects',
    //     () async {
    //   final appTips = await tippingService.getLegacyAppTips();
    //   expect(appTips, isA<List<GsheetAppTip>>());
    // });

    test('syncTipsToLegacy should return a String', () async {
      TippersViewModel tipperViewModel = TippersViewModel();
      DAUComp testingDAUComp = DAUComp(
        dbkey: '-Nk88l-ww9pYF1j_jUq7',
        name: 'Testing DAUComp',
        aflFixtureJsonURL: Uri.parse('https://www.google.com'),
        nrlFixtureJsonURL: Uri.parse('https://www.google.com'),
      );
      GamesViewModel gamesViewModel =
          GamesViewModel(testingDAUComp); //TODO remove hard coding
      final allTipsViewModel =
          TipsViewModel(tipperViewModel, testingDAUComp.dbkey!, gamesViewModel);
      final daucompsViewModel = DAUCompsViewModel(testingDAUComp.dbkey!);
      final result = await tippingService.syncAllTipsToLegacy(
          allTipsViewModel, daucompsViewModel);
      expect(result, isA<String>());
    });
  });
}
