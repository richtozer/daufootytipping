import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_login_issue_screen.dart';
import 'package:daufootytipping/view_models/config_viewmodel.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/search_query_provider.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
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
  StartupProfiling.instant('startup.main_entered');
  StartupProfiling.start('startup.tips_page_stable');
  StartupProfiling.start('startup.tips_content_ready');
  const bool useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: true,
  );
  const String configuredFirebaseEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );
  final String firebaseEmulatorHost = configuredFirebaseEmulatorHost.isNotEmpty
      ? configuredFirebaseEmulatorHost
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
      ? '10.0.2.2'
      : 'localhost';

  // Do not start running the application widget code until the Flutter framework is completely booted
  WidgetsFlutterBinding.ensureInitialized();

  // On web, the App Check debug token must be set before Firebase is initialized.
  if (kIsWeb) {
    if (kDebugMode) {
      js.context['FIREBASE_APPCHECK_DEBUG_TOKEN'] = true;
      log('FIREBASE_APPCHECK_DEBUG_TOKEN set to true');
    } else {
      js.context['FIREBASE_APPCHECK_DEBUG_TOKEN'] = false;
      log('FIREBASE_APPCHECK_DEBUG_TOKEN set to false');
    }
  }

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // If in release mode, pass all uncaught "fatal" errors from the framework to Crashlytics
  // same for async platform errors
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
      providerAndroid: const AndroidPlayIntegrityProvider(),
      providerApple: const AppleAppAttestProvider(),
      providerWeb: ReCaptchaEnterpriseProvider(
        '6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E',
      ),
    );
    log('FirebaseAppCheck activated');
  } else {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidDebugProvider(),
        providerApple: const AppleDebugProvider(),
        providerWeb: ReCaptchaEnterpriseProvider(
          //temporarily use prod key in debug
          '6Lfv1ZYpAAAAAF7npOM-PQ_SfIJnLob02ES9On_E',
        ),
      );
      log('FirebaseAppCheck activated in debug mode');
    } catch (error, stackTrace) {
      if (kIsWeb) {
        log(
          'FirebaseAppCheck debug activation failed on web; continuing for local debug.',
          error: error,
          stackTrace: stackTrace,
        );
      } else {
        rethrow;
      }
    }
  }

  FirebaseDatabase database = FirebaseDatabase.instance;
  if (kDebugMode && useFirebaseEmulators) {
    database.useDatabaseEmulator(firebaseEmulatorHost, 8000);
    log('Database emulator started on $firebaseEmulatorHost:8000');
  } else {
    if (!kIsWeb) {
      database.setPersistenceCacheSizeBytes(100 * 1024 * 1024); // 100 MB
      database.setPersistenceEnabled(true);
      log('Database persistence enabled (100 MB cache)');
    }

    if (kDebugMode) {
      log(
        'Database emulator disabled for debug build (USE_FIREBASE_EMULATORS=false).',
      );
    }
  }

  // use emulator for firestore document collection when in debug mode
  if (kDebugMode && useFirebaseEmulators) {
    FirebaseFirestore.instance.useFirestoreEmulator(firebaseEmulatorHost, 8081);
    log('Firestore emulator started on $firebaseEmulatorHost:8081');
  } else if (kDebugMode) {
    log(
      'Firestore emulator disabled for debug build (USE_FIREBASE_EMULATORS=false).',
    );
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
  StartupProfiling.instant('startup.run_app_called');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _registeredActiveCompKey;
  bool? _registeredCreateLinkedTipper;

  void _registerCoreViewModelsIfNeeded(ConfigViewModel configViewModel) {
    final String activeCompKey = configViewModel.activeDAUComp!;
    final bool createLinkedTipper = configViewModel.createLinkedTipper!;

    if (!di.isRegistered<TeamsViewModel>()) {
      di.registerLazySingleton<TeamsViewModel>(() => TeamsViewModel());
    }

    final bool needsRegistration =
        !di.isRegistered<DAUCompsViewModel>() ||
        !di.isRegistered<TippersViewModel>() ||
        _registeredActiveCompKey != activeCompKey ||
        _registeredCreateLinkedTipper != createLinkedTipper;

    if (needsRegistration) {
      _registeredActiveCompKey = activeCompKey;
      _registeredCreateLinkedTipper = createLinkedTipper;

      di.registerLazySingleton<TippersViewModel>(
        () => TippersViewModel(createLinkedTipper),
      );
      di.registerLazySingleton<DAUCompsViewModel>(
        () => DAUCompsViewModel(activeCompKey, false),
      );
    }

    // Warm the realtime listeners while auth/cache work is still in flight.
    di<TeamsViewModel>();
    di<TippersViewModel>();
    di<DAUCompsViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'app',
      theme: FlexThemeData.light(scheme: FlexScheme.green),
      darkTheme: FlexThemeData.dark(scheme: FlexScheme.green),
      themeMode: ThemeMode.system,
      title: 'DAU Tips',
      home: LayoutBuilder(
        builder: (context, constraints) {
          // Set the maximum width of the app
          const maxWidth = 500.0; // Adjust this value as needed
          // Calculate the width to be used, ensuring it does not exceed maxWidth
          final width = constraints.maxWidth > maxWidth
              ? maxWidth
              : constraints.maxWidth;

          return Center(
            child: SizedBox(
              width: width,
              child: Consumer<ConfigViewModel>(
                builder: (context, configViewModel, child) {
                  return FutureBuilder<void>(
                    future: configViewModel.initialLoadComplete,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: League.afl.colour,
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return LoginIssueScreen(
                          message:
                              'Unexpected startup error. ${snapshot.error}',
                          displaySignOutButton: false,
                        );
                      }

                      // if required config is missing, display error
                      if (!configViewModel.hasRequiredBootstrapConfig) {
                        // display LoginErrorScreen
                        return LoginIssueScreen(
                          message:
                              'Unexpected startup error. Contact support: https://interview.coach/tipping',
                          displaySignOutButton: false,
                        );
                      } else {
                        _registerCoreViewModelsIfNeeded(configViewModel);

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
