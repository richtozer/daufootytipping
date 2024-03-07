import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
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
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(); // Loads .env file

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

  RemoteConfigService remoteConfigService = RemoteConfigService();
  String configDAUComp = await remoteConfigService.getConfigCurrentDAUComp();

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // setup some default analytics parameters
  FirebaseAnalytics.instance.setDefaultEventParameters({'version': '1.0.0'});

  FirebaseService firebaseService = FirebaseService();
  firebaseService.initializeFirebaseMessaging();

  // register the viewmodels for later use using dependency injection (Get_it/watch_it)
  di.allowReassignment = true;
  di.registerLazySingleton<LegacyTippingService>(() => LegacyTippingService());
  di.registerSingleton<PackageInfoService>(PackageInfoService());

  di.registerLazySingleton<TippersViewModel>(
      () => TippersViewModel(firebaseService));

  di.registerLazySingleton<DAUCompsViewModel>(
      () => DAUCompsViewModel(configDAUComp));
  di.registerLazySingleton<TeamsViewModel>(() => TeamsViewModel());

  DAUComp? dAUComp = await di<DAUCompsViewModel>().getCurrentDAUComp();

  di.registerLazySingleton<GamesViewModel>(() => GamesViewModel(dAUComp!));

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
