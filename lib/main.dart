import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:daufootytipping/services/google_sheet_service.dart.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/theme_data.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
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

  await dotenv.load(); // Loads .env file

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Enable persistence for Realtime Database
  FirebaseDatabase.instance.setPersistenceEnabled(true);

  if (kDebugMode) {
    FirebaseDatabase database = FirebaseDatabase.instance;
    database.useDatabaseEmulator('http://localhost', 8000);

    FirebaseAuth.instance.useAuthEmulator('http://localhost', 8099);
  }

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

  FirebaseService firebaseService = FirebaseService();
  await firebaseService.initializeFirebaseMessaging();

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
  await FirebaseAnalytics.instance
      .setDefaultEventParameters({'version': '1.0.0'});

  final locator = GetIt.instance;
  locator.registerSingleton<LegacyTippingService>(LegacyTippingService());
  locator.registerSingleton<PackageInfoService>(PackageInfoService());

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
    return ChangeNotifierProvider<DAUCompsViewModel>(
        create: (_) => DAUCompsViewModel(
              configDAUComp,
            ), // Pass the argument here
        child: MaterialApp(
          theme: myTheme,
          title: 'DAU Tips',
          home: UserAuthPage(remoteConfigService, firebaseService),
        ));
  }
}
