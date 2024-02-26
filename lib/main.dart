import 'dart:developer';

import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Do not to start running the application widget code until the Flutter framework is completely booted
  log('aaa main 1');

  WidgetsFlutterBinding.ensureInitialized();

  log('aaa main 2');

  await dotenv.load(); // Loads .env file

  log('aaa main 3');

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  log('aaa main 4');
  if (!kDebugMode) {
    // in release mode, enable persistence for Realtime Database
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } else {
    FirebaseDatabase.instance.setPersistenceEnabled(false);
  }

/*   if (kDebugMode) {
    FirebaseDatabase database = FirebaseDatabase.instance;
    database.useDatabaseEmulator('http://localhost', 8000);

    FirebaseAuth.instance.useAuthEmulator('http://localhost', 8099);
  } */

  log('aaa main 5');

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

  log('aaa main 6');

  RemoteConfigService remoteConfigService = RemoteConfigService();
  String configDAUComp = await remoteConfigService.getConfigCurrentDAUComp();

  log('aaa main 7');

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  log('aaa main 8');

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  log('aaa main 9');

  // setup some default analytics parameters
  FirebaseAnalytics.instance.setDefaultEventParameters({'version': '1.0.0'});

  log('aaa main 10');

  FirebaseService firebaseService = FirebaseService();
  firebaseService.initializeFirebaseMessaging();

  log('aaa main 11');
  // register the viewmodels for later use using dependency injection (Get_it/watch_it)
  final locator = GetIt.instance;
  locator.allowReassignment = true;
  locator.registerSingleton<LegacyTippingService>(LegacyTippingService());
  log('main 11');
  locator.registerSingleton<PackageInfoService>(PackageInfoService());
  locator.registerLazySingleton<ScoresViewModel>(
      () => ScoresViewModel(configDAUComp));
  locator.registerLazySingleton<TippersViewModel>(
      () => TippersViewModel(firebaseService));

  locator.registerLazySingleton<DAUCompsViewModel>(
      () => DAUCompsViewModel(configDAUComp));
  locator.registerLazySingleton<TeamsViewModel>(() => TeamsViewModel());

  DAUComp? dAUComp = await di<DAUCompsViewModel>().getCurrentDAUComp();
  locator.registerLazySingleton<GamesViewModel>(() => GamesViewModel(dAUComp!));

  log('aaa main 12');

  runApp(MyApp(remoteConfigService, configDAUComp, firebaseService));
}

class MyApp extends StatelessWidget {
  final RemoteConfigService remoteConfigService;
  final String configDAUComp;
  final FirebaseService firebaseService;
  const MyApp(
      this.remoteConfigService, this.configDAUComp, this.firebaseService,
      {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: myTheme,
      title: 'DAU Tips',
      home: UserAuthPage(configDAUComp, remoteConfigService, firebaseService),
    );
  }
}
