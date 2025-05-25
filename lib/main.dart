import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/search_query_provider.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'firebase_options.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:universal_html/js.dart' as js;

Future<void> main() async {
  // Do not start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // If in release mode, pass all uncaught "fatal" errors from the framework to Crashlytics
  // same for async platfrom errors
  if (!kDebugMode) {
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  if (!kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest,
      webProvider: ReCaptchaEnterpriseProvider(
          '6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E'),
    );
    log('FirebaseAppCheck activated');
  } else {
    await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
        // webProvider: ReCaptchaEnterpriseProvider(
        //     '6LegwxcqAAAAAEga5YMkA8-ldXP18YytlFTgiJl9'));
        webProvider:
            ReCaptchaEnterpriseProvider(//temporarily use prod key in debug
                '6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E'));
    log('FirebaseAppCheck activated in debug mode');
  }

  if (kIsWeb) {
    if (kDebugMode) {
      js.context['FIREBASE_APPCHECK_DEBUG_TOKEN'] = true;
      log('FIREBASE_APPCHECK_DEBUG_TOKEN set to true');
    } else {
      js.context['FIREBASE_APPCHECK_DEBUG_TOKEN'] = false;
      log('FIREBASE_APPCHECK_DEBUG_TOKEN set to false');
    }
  }

  FirebaseDatabase database = FirebaseDatabase.instance;
  if (kDebugMode) {
    database.useDatabaseEmulator('localhost', 8000);
    log('Database emulator started');
  } else {
    if (!kIsWeb) {
      database.setPersistenceEnabled(true);
      log('Database persistence enabled');
    }
  }

  // use emulator for firestore document collection when in debug mode
  if (kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8081);
    log('Firestore emulator started');
  }

  di.allowReassignment = true;

  di.registerLazySingleton<PackageInfoService>(() => PackageInfoService());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SearchQueryProvider()),
        ChangeNotifierProvider(create: (context) => ConfigViewModel()),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
              child: Consumer<ConfigViewModel>(
                builder: (context, configViewModel, child) {
                  return FutureBuilder<void>(
                    future: configViewModel.initialLoadComplete,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: League.afl.colour,
                          ),
                        );
                      }

                      // if config is null display error
                      if (configViewModel.activeDAUComp == null) {
                        // display LoginErrorScreen
                        return LoginIssueScreen(
                          message:
                              'Unexpected startup error. Contact support: https://interview.coach/tipping',
                          displaySignOutButton: false,
                        );
                      } else {
                        di.registerLazySingleton<DAUCompsViewModel>(() =>
                            DAUCompsViewModel(
                                configViewModel.activeDAUComp!, false));

                        di.registerLazySingleton<TippersViewModel>(() =>
                            TippersViewModel(
                                configViewModel.createLinkedTipper!));

                        return UserAuthPage(
                          configViewModel.minAppVersion,
                          isUserLoggingOut: false,
                          createLinkedTipper:
                              configViewModel.createLinkedTipper!,
                          googleClientId: configViewModel.googleClientId ?? '',
                        );
                      }
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
