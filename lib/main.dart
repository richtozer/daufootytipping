import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/appstate_viewmodel.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

Future<void> main() async {
  // Do not to start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

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

  //initialize firebase messaging
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  //Request notification permissions (iOS only):
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  RemoteConfigService remoteConfigService = RemoteConfigService();

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // setup some default analytics parameters
  await FirebaseAnalytics.instance
      .setDefaultEventParameters({'version': '1.0.0'});

  await dotenv.load(); // Loads .env file

  final locator = GetIt.instance;
  locator.registerSingleton<LegacyTippingService>(LegacyTippingService());
  locator.registerSingleton<PackageInfoService>(PackageInfoService());

  //TEST

  /*  DAUComp daucomp = DAUComp(
    dbkey: '-Nk88l-ww9pYF1j_jUq7',
    name: 'DAU Footy Tipping 2024.98',
    aflFixtureJsonURL: Uri(
        scheme: 'https',
        host: 'fixturedownload.com',
        path: 'feed/json/afl-2024'),
    nrlFixtureJsonURL: Uri(
        scheme: 'https',
        host: 'fixturedownload.com',
        path: 'feed/json/nrl-2024'),
  );

  DAUCompsViewModel dcvm = DAUCompsViewModel();
  dcvm.getNetworkFixtureData(daucomp); */

  //TEST

  runApp(MyApp(remoteConfigService));
}

class MyApp extends StatelessWidget {
  final RemoteConfigService remoteConfigService;
  const MyApp(this.remoteConfigService, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: myTheme,
      title: 'DAU Footy Tipping',
      home: UserAuthPage(remoteConfigService),
    );
  }
}
