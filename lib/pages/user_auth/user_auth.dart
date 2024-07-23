import 'dart:developer';
import 'package:daufootytipping/main.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_apple/firebase_ui_oauth_apple.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watch_it/watch_it.dart';

class UserAuthPage extends StatelessWidget {
  final String currentDAUCompKey;
  final String? configMinAppVersion;

  bool isUserLoggingOut = false;
  bool isUserDeletingAccount = false;

  UserAuthPage(this.currentDAUCompKey, this.configMinAppVersion,
      {super.key,
      this.isUserLoggingOut = false,
      this.isUserDeletingAccount = false});

  var clientId = dotenv.env['GOOGLE_CLIENT_ID']!;

  PackageInfoService packageInfoService = GetIt.instance<PackageInfoService>();

  Future<bool> isClientVersionOutOfDate() async {
    //skip version check if the configMinAppVersion is null
    if (configMinAppVersion == null) {
      return false;
    }
    PackageInfo packageInfo = await packageInfoService.packageInfo;

    List<String> currentVersionParts = packageInfo.version.split('.');
    List<String> newVersionParts = configMinAppVersion!.split('.');

    for (int i = 0; i < newVersionParts.length; i++) {
      int currentPart = int.parse(currentVersionParts[i]);
      int newPart = int.parse(newVersionParts[i]);

      if (newPart > currentPart) {
        return true;
      } else if (newPart < currentPart) {
        return false;
      }
    }

    // If we get to this point, the versions are equal
    return false;
  }

  // method to log user out
  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    log('UserAuthPage.build()');
    if (isUserLoggingOut) {
      signOut();
      log('UserAuthPage.build() - user signed out');
      // return to the main app
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (BuildContext context) =>
                  MyApp(null, currentDAUCompKey)),
          (Route<dynamic> route) => false,
        );
      });
    }
    if (isUserDeletingAccount) {
      di<TippersViewModel>().deleteAccount();
      log('UserAuthPage.build() - user deleted account');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (BuildContext context) =>
                  MyApp(null, currentDAUCompKey)),
          (Route<dynamic> route) => false,
        );
      });
    }

    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          // check if the current app version is lower than the value set in
          // remote config, if so, force the user to update the app
          return FutureBuilder<bool>(
            future: isClientVersionOutOfDate(),
            builder: (context, versionSnapshot) {
              if (versionSnapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: League.afl.colour));
              }
              if (versionSnapshot.data == true) {
                //,
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(height: 50),
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Image(
                          height: 110,
                          width: 110,
                          image: AssetImage('assets/icon/AppIcon.png'),
                        ),
                      ),
                      SizedBox(height: 20),
                      SizedBox(
                        width: 300,
                        child: Center(
                          child: Card(
                            color: Colors.red,
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Text(
                                "This version of the app is no longer supported, please update the app from the app store.",
                                style: TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (!authSnapshot.hasData) {
                return SignInScreen(
                  providers: [
                    AppleProvider(),
                    GoogleProvider(clientId: clientId),
                    EmailAuthProvider(),
                  ],
                  headerBuilder: (context, constraints, shrinkOffset) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image(
                          image: AssetImage('assets/icon/AppIcon.png'),
                        ),
                      ),
                    );
                  },
                  subtitleBuilder: (context, action) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: action == AuthAction.signIn
                          ? const Text(
                              'Welcome to DAU Footy Tipping, please sign in!')
                          : const Text(
                              'Welcome to DAU Footy Tipping, please sign up!'),
                    );
                  },
                  footerBuilder: (context, action) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'By signing in, you ackonwledge you are a paid up member of DAU Footy Tipping.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  },
                );
              }

              //once we pass signin we have a firebase auth user context
              User? authenticatedFirebaseUser = authSnapshot.data;
              if (authenticatedFirebaseUser == null) {
                return const LoginErrorScreen(
                    errorMessage:
                        'No user context found. Please contact daufootytipping@gmail.com');
              }
              if (authenticatedFirebaseUser.isAnonymous) {
                return const LoginErrorScreen(
                    errorMessage:
                        'You have logged in as anonymous. Please contact daufootytipping@gmail.com');
              }
              if (authenticatedFirebaseUser.emailVerified == false) {
                return const LoginErrorScreen(
                    errorMessage:
                        'Your email is not verified. Please contact daufootytipping@gmail.com');
              }

              //at this point we have a verfied logged on user - as we send them
              //to the home page, make sure they are represented in the realtime database
              // as a tipper linked to their firebase auth record,
              //if not create a Tipper record for them.

              FirebaseAnalytics.instance.logLogin(
                  loginMethod:
                      authenticatedFirebaseUser.providerData[0].providerId);

              TippersViewModel tippersViewModel = di<TippersViewModel>();

              return FutureBuilder<bool>(
                future: tippersViewModel.linkUserToTipper(),
                builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                        child: CircularProgressIndicator(
                            color: League.afl.colour));
                  } else if (snapshot.hasError) {
                    return LoginErrorScreen(
                        errorMessage:
                            'Unexpected error ${snapshot.error}. Contact daufootytipping@gmail.com');
                  } else if (snapshot.data == null) {
                    return const LoginErrorScreen(
                        errorMessage:
                            'Unexpected null from linkUserToTipper. Contact daufootytipping@gmail.com');
                  } else {
                    // snapshot.data will be true if there is an existing tipper record, otherwise false
                    if (snapshot.data == false) {
                      // display an error if no tipper record is found
                      return LoginErrorScreen(
                          errorMessage:
                              'No tipper record found for login: ${authenticatedFirebaseUser.email}. Contact daufootytipping@gmail.com');
                    }

                    return HomePage(currentDAUCompKey);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

class LoginErrorScreen extends StatelessWidget {
  final String errorMessage;

  const LoginErrorScreen({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 50),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Image(
                height: 110,
                width: 110,
                image: AssetImage('assets/icon/AppIcon.png'),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 300,
              child: Center(
                child: Card(
                  color: Colors.red,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 150,
              child: OutlinedButton(
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout),
                    Text('Sign Out'),
                  ],
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => UserAuthPage(
                        di<DAUCompsViewModel>().selectedDAUComp!.dbkey!,
                        null,
                        isUserLoggingOut: true,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
