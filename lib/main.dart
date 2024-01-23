import 'dart:developer';

import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/appstate_viewmodel.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:gsheets/gsheets.dart';

Future<void> main() async {
  // Do not to start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

  await updateSheetData();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
      webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  }

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // setup some default analytics parameters
  await FirebaseAnalytics.instance
      .setDefaultEventParameters({'version': '1.2.3'});

  await dotenv.load(); // Loads .env file

  final locator = GetIt.instance;
  locator.registerSingleton<LegacyTippingService>(LegacyTippingService());
  locator.registerSingleton<PackageInfoService>(PackageInfoService());

  runApp(const MyApp());
}

var _credentials = {
  "type": "service_account",
  "project_id": dotenv.env['PROJECT_ID'],
  "private_key_id": dotenv.env['PRIVATE_KEY_ID'],
  "private_key":
      "[REDACTED_PRIVATE_KEY]\n",
  "client_email": dotenv.env['CLIENT_EMAIL'],
  "client_id": dotenv.env['CLIENT_ID'],
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url":
      "https://www.googleapis.com/robot/v1/metadata/x509/[REDACTED_SERVICE_ACCOUNT]",
  "universe_domain": "googleapis.com"
};

Future<void> updateSheetData() async {
  await dotenv.load(); //

  // Initialize the GSheets service
  final gsheets = GSheets(_credentials);

  // Specify the spreadsheet and the worksheet
  final ss = await gsheets.spreadsheet(dotenv.env['DAU_GSHEET_ID']!);
  final sheet = ss.worksheetByTitle('Sheet15');

  // Fetch all rows
  final List<List<String>>? values = await sheet?.values.allRows();

  // if the sheet is empty, another process if writing a change
  // wait a few seconds and try again
  if (values == null) {
    await Future.delayed(const Duration(seconds: 5));
    return updateSheetData();
  }

  // Make some changes to the data
  for (var row in values) {
    for (var i = 0; i < row.length; i++) {
      row[i] = '${row[i]}_updated'; // Append '_updated' to each cell
    }
  }

  // Clear the sheet
  await sheet?.clear();

  // Write the changes back to the sheet
  try {
    //await sheet?.values.insertRow(1, values);
    await sheet?.values.appendRows(values);
  } catch (e) {
    log(e.toString());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        theme: myTheme,
        title: 'DAU Footy Tipping',
        home: UserAuthPage(),
      ),
    );
  }
}
