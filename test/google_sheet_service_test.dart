import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:test/test.dart';
import 'firebase_database_mock.dart';

void main() {
  setupFirebaseDatabaseMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    await dotenv.load(); // Loads .env file
  });

  // Define a group of tests
  group('LegacyTippingService tests', () {
    // Each test in the group starts with the test() function
    test('.submitDefaultTips() submits default tips', () async {
      // TODO - getting error when setting up the listener in tipperviewmodel
      // see here for options to fix: https://docs.flutter.dev/testing/plugins-in-tests
      // error is:
      //
      // MissingPluginException(No implementation found for method Query#observe on channel plugins.flutter.io/firebase_database)
      // package:flutter/src/services/platform_channel.dart 320:7                                         MethodChannel._invokeMethod
      // ===== asynchronous gap ===========================
      // dart:async                                                                                       _CustomZone.registerBinaryCallback
      // package:firebase_database_platform_interface/src/method_channel/method_channel_query.dart 48:25  MethodChannelQuery.observe
      // ===== asynchronous gap ===========================
      // dart:async                                                                                       _ForwardingStream.listen
      // package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart 44:54                   TippersViewModel._listenToTippers
      // package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart 39:5                    new TippersViewModel
      // test/google_sheet_service_test.dart 22:43                                                        main.<fn>.<fn>

      TippersViewModel tippersViewModel = TippersViewModel();
      List<Tipper> tippers = await tippersViewModel.getTippers();
      GamesViewModel gamesViewModel = GamesViewModel("-Nk88l-ww9pYF1j_jUq7");

      LegacyTippingService service = LegacyTippingService();
      await service.submitLegacyDefaultTips(tippers, gamesViewModel);

      expect(service.appTipsData?[0][0], equals(['foo', 'bar', 'baz']));
    });
  });
}

/*
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:gsheets/gsheets.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart'; // Or any other mocking library you prefer



class MockSheetsApi extends Mock implements SheetsApi {}
class MockGSheets extends Mock implements GSheets {}

// Instantiate mocks for each test
final mockSheetsApi = MockSheetsApi();
final mockGSheets = MockGSheets();

void main() {
  group('LegacyTippingService tests', () {
    
    test('submitDefaultTips() correctly updates default tips in the sheet', () async {
  // Set up mock responses for initial data and batch update
  when(mockSheetsApi.spreadsheets.values.get(any, any))
      .thenAnswer((_) async => ValueRange()); // Initial data
  when(mockSheetsApi.spreadsheets.batchUpdate(any, any))
      .thenAnswer((_) async => BatchUpdateSpreadsheetResponse()); // Update success

  final service = LegacyTippingService(
      sheetsApi: mockSheetsApi, gsheets: mockGSheets);
  await service._initialize();

  // ... (set up tippers and gamesViewModel for the test)

  await service.submitDefaultTips(tippers, gamesViewModel);

  // Verify that the batch update was called with expected data
  verify(mockSheetsApi.spreadsheets.batchUpdate(
      any, captureThat(isA<BatchUpdateSpreadsheetRequest>())));

  // ... (assert that the expected data was sent in the update request)
});

test('submitDefaultTips() handles different round combinations', () async {
  // ... (set up mocks and service)

  // Simulate different combinedRounds from gamesViewModel
  when(gamesViewModel.getCombinedRoundNumbers())
      .thenReturn([1, 4, 7]); // Example round combination

  await service.submitDefaultTips(tippers, gamesViewModel);

  // Verify that the update only includes those rounds
  // ... (assert that only columns for rounds 1, 4, and 7 were updated)
});


test('submitDefaultTips() preserves existing tips when applicable', () async {
  // ... (set up mocks and service)

  // Set up initial data with existing tips
  service.appTipsData = [
    ['Tipper1', '12345678901234567'],
    // ...
  ];

  // ... (set up tippers and gamesViewModel)

  await service.submitDefaultTips(tippers, gamesViewModel);

  // Verify that existing tips were preserved
  // ... (assert that the expected cells retain their original values)
});

test('submitDefaultTips() retries on errors', () async {
  // ... (set up mocks and service)

  when(mockSheetsApi.spreadsheets.batchUpdate(any, any))
      .thenThrow(Exception('Error')); // Simulate error

  await service.submitDefaultTips(tippers, gamesViewModel);

  // Verify that the batch update was called multiple times (due to retries)
  verify(mockSheetsApi.spreadsheets.batchUpdate(any, any)).called(5);

  // ... (assert that the error was eventually logged or handled appropriately)
});

    
  });
}

*/
