import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_games_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_scoring_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_home/alltips_viewmodel.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Do not start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(); // Loads .env file

  // if (kIsWeb) {
  //   bool ready = await GRecaptchaV3.ready(
  //       "6LfmjfUlAAAAAF0dxFR_6L4BerFoRLEA3iCDxhlI",
  //       showBadge: true);
  //   log("Is Recaptcha ready? $ready");
  // }

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseDatabase database = FirebaseDatabase.instance;
  if (kDebugMode) {
    database.useDatabaseEmulator('localhost', 8000);

    //FirebaseAuth.instance.useAuthEmulator('http://localhost', 8099);
  } else {
    database.setPersistenceEnabled(true);
  }

  if (!kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
      webProvider:
          ReCaptchaV3Provider('6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E'),
    );
    // } else {
    //   await FirebaseAppCheck.instance.activate(
    //     androidProvider: AndroidProvider.debug,
    //     appleProvider: AppleProvider.debug,
    //     webProvider:
    //         ReCaptchaV3Provider('6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E'),
    //   );
  }

  RemoteConfigService remoteConfigService = RemoteConfigService();
  String configDAUComp = await remoteConfigService.getConfigCurrentDAUComp();
  String configMinAppVersion =
      await remoteConfigService.getConfigMinAppVersion();
  bool createLinkedTipper = await remoteConfigService.getCreateLinkedTipper();

  // If in release mode, pass all uncaught "fatal" errors from the framework to Crashlytics
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // setup some default analytics parameters
  // if (!kIsWeb) {
  //   FirebaseAnalytics.instance.setDefaultEventParameters({'version': '1.0.0'});
  // }

  // register the viewmodels for later use using dependency injection (Get_it/watch_it)
  //di.allowReassignment = true;

  if (!kIsWeb) {
    // setup Firebase Messaging Service
    di.registerLazySingleton<FirebaseMessagingService>(
        () => FirebaseMessagingService());
    di<FirebaseMessagingService>().initializeFirebaseMessaging();
  }

  di.registerLazySingleton<TippersViewModel>(
      () => TippersViewModel(createLinkedTipper));

  di.registerLazySingleton<LegacyTippingService>(() => LegacyTippingService());
  di.registerLazySingleton<PackageInfoService>(() => PackageInfoService());

  di.registerLazySingleton<DAUCompsViewModel>(
      () => DAUCompsViewModel(configDAUComp));
  di.registerLazySingleton<TeamsViewModel>(() => TeamsViewModel());

  DAUComp? dAUComp = await di<DAUCompsViewModel>().getCurrentDAUComp();

  di.registerLazySingleton<GamesViewModel>(() => GamesViewModel(dAUComp!));
  di.registerLazySingleton<ScoresViewModel>(
      () => ScoresViewModel(dAUComp!.dbkey!));

  // register TipsViewModel for later use
  di.registerLazySingleton<TipsViewModel>(() => TipsViewModel(
      di<TippersViewModel>(),
      di<DAUCompsViewModel>().selectedDAUComp!.dbkey!,
      di<GamesViewModel>()));

  // run the application widget code

  runApp(MyApp(configMinAppVersion, configDAUComp));
}

class MyApp extends StatelessWidget {
  final String? configMinAppVersion;
  final String configDAUComp;
  const MyApp(this.configMinAppVersion, this.configDAUComp, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FlexThemeData.light(scheme: FlexScheme.green),
      darkTheme: FlexThemeData.dark(scheme: FlexScheme.green),
      themeMode: ThemeMode.system,
      title: 'DAU Tips',
      home: UserAuthPage(configDAUComp, configMinAppVersion),
    );
  }
}
