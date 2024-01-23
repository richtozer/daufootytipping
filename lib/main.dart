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
      "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC+WAd7eZ3U9EU6\nAqCkYIBqE9buYBejA1vQm3V+tsfTSpR7OXFZqtXjUlrIP48TmtGOoTgZEUgFdIE0\nqnTKe4Ufnm98+g0wg1vDDAoJ2f9zSS4U54larHFDAYIUfV2m2k5rUvlMH4Sl352x\nJfgw/xg/VaSC18CL6Ho1yYyFoGliyIWTb0GvKaeeKcZnd8pxEPTfToFCuPu1I+HY\n7G/14kx7meCrSiPJXnOSq4R6DHApBAm5IKsBxQm/pL2MPbe4X4hM63APx54kVij2\n+m+4DoP67Fs1gr6Jcri49Uw9QD/XGUVJ1CGWHkw+/gD+eBKpZDYYgXLWIwiH39k5\nIUs3flMrAgMBAAECggEAXHTS8Zmh3jJmu+ZR1HZheeU4JeK8KHz1qK8Sk+HBz3Kv\nC+nbkrQGH9y9Zv5kh5/QgYjzAE4iHzA3oHbZsw7rm2+wdNLa/EEaHfRnneBrkjqu\nLQ5IbChN/b+qSTyZ9HWe2MfdeynmG1IyvT0VwOrwAredaMbW6r6aOi0z2iaQeh/Y\nwqm9cHgTTQt2884QmN1g5SiI5hz9EjDVOfW+tesemU6EQu8Kuh8Y2WN7wifEa3Ck\ngLc/Ea4GwjtPeGUKh0qd1cd+SrOU3zc46bgqq60rT3X3AevQG9/jhZb2mRA0JheR\ngyS1+dPWRw3E3HKJ//DS7lrrZ91mac9N3wHvgVm0dQKBgQDr3756fPi7tZwP5tZ0\nT2CsGLDK5rXkWPnQwqwHtyJjU5fFNYLl//x1V0slvN+348y0PS+UOZhJHq3J+6r1\nNaq1nj2pCVjmDYJwiY0cPZjTsHjXso7Ig5z7jf8yxF9r/v2LBG9AEzX/SJsDeUPO\ngm7FNq7uiTZCKJqroUsnkK0M5QKBgQDOlcJAkN4avTbEvxVBoi1mtRC34M3M7WOC\noqiLLnyEFkVheQZWG569zQHs7PiewH9BsLbfLmTXPYfeKetH8Cqt3yPteLtzItIY\nTYIinxRcwlhHv98SdQ26IdeNEcZ+J+0GFn4DxPDEkdTDUdyga6Eks0cAM/DB5CLD\n/kA7LgTuzwKBgQDP2B/LZVX0aepz5K/yW4PPAg6/LB75cSHov7HBNrGZnq5s+2M1\n8qTubRZt0Ym9S4E1DXlgfoPfYqY3Bom1ey3Kzf59dhwc06iuK7bpPKnvV2CUiOXi\ncH8i9xP6EyoWSuH13tl9N7BsG/lkTTXfwfWD2FS7IrNqBseMFxvXaFfktQKBgHUB\nj29AXfvpFV8kFycAcxSMEzcCZa3e+pCgDjQelTm+33cQtA0LQcKgnamSolJQFwOe\n0kTgIw9h81Vair9JAPNPwiqbShgxLavEIqP3U/IhxRyGSRNMJwU4a7yjx7fmZzIe\nhSsfXXsIWehysjJOI4wE2n777C31R9eYZsreCr8zAoGBANuHKD+ax9Acs0yUYKJ8\nphbdbc0oNUENm7EvGt+X8HOe262XyzwhtBGzbelNX5qjCHDzbUHqhaTiSV9gWCk1\nZLIS9XqSRmSL2gRd5ENlTJpsGulwLBAJaDL/muTbbq23RnV6iTmkIZErKvHxRWsi\nCWCapx/tX67zRMnDnE6l+xKT\n-----END PRIVATE KEY-----\n",
  "client_email": dotenv.env['CLIENT_EMAIL'],
  "client_id": dotenv.env['CLIENT_ID'],
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url":
      "https://www.googleapis.com/robot/v1/metadata/x509/sheets%40dau-footy-tipping-f8a42.iam.gserviceaccount.com",
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
