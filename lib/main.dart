import 'dart:developer';

import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:g_recaptcha_v3/g_recaptcha_v3.dart';
import 'package:watch_it/watch_it.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  // Do not start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "./dotenv"); // Loads .env file

  if (kIsWeb) {
    bool ready = await GRecaptchaV3.ready(
        "6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E",
        showBadge: true);
    log("Is Recaptcha ready? $ready");
  }

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
      webProvider:
          ReCaptchaV3Provider('6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E'),
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
      webProvider:
          ReCaptchaV3Provider('6LegwxcqAAAAAEga5YMkA8-ldXP18YytlFTgiJl9'),
    );
  }
  FirebaseDatabase database = FirebaseDatabase.instance;
  if (kDebugMode) {
    database.useDatabaseEmulator('localhost', 8000);
  } else {
    if (!kIsWeb) {
      database.setPersistenceEnabled(true);
    }
  }

  RemoteConfigService remoteConfigService = RemoteConfigService();
  String activeDAUCompDbkey =
      await remoteConfigService.getConfigCurrentDAUComp();
  String configMinAppVersion =
      await remoteConfigService.getConfigMinAppVersion();
  bool createLinkedTipper = await remoteConfigService.getCreateLinkedTipper();

  // If in release mode, pass all uncaught "fatal" errors from the framework to Crashlytics
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  //setup some default analytics parameters
  if (!kIsWeb) {
    FirebaseAnalytics.instance.setDefaultEventParameters({'version': '1.2.0'});
  }

  di.allowReassignment = true;

  if (!kIsWeb) {
    di.registerLazySingleton<FirebaseMessagingService>(
        () => FirebaseMessagingService());
    di<FirebaseMessagingService>().initializeFirebaseMessaging();
  }

  di.registerLazySingleton<TippersViewModel>(
      () => TippersViewModel(createLinkedTipper));

  di.registerLazySingleton<PackageInfoService>(() => PackageInfoService());

  di.registerLazySingleton<DAUCompsViewModel>(
      () => DAUCompsViewModel(activeDAUCompDbkey));
  di.registerLazySingleton<TeamsViewModel>(() => TeamsViewModel());

  runApp(MyApp(configMinAppVersion));
}

class MyApp extends StatelessWidget {
  final String? configMinAppVersion;
  const MyApp(this.configMinAppVersion, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: FlexThemeData.light(scheme: FlexScheme.green),
      darkTheme: FlexThemeData.dark(scheme: FlexScheme.green),
      themeMode: ThemeMode.system,
      title: 'DAU Tips',
      home: LayoutBuilder(
        builder: (context, constraints) {
          // Set the maximum width of the app
          const maxWidth = 500.0; // Adjust this value as needed
          // Calculate the width to be used, ensuring it does not exceed maxWidth
          final width =
              constraints.maxWidth > maxWidth ? maxWidth : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: width,
              child: UserAuthPage(configMinAppVersion),
            ),
          );
        },
      ),
    );
  }
}
