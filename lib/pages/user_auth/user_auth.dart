import 'dart:developer';
import 'package:daufootytipping/main.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_apple/firebase_ui_oauth_apple.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:watch_it/watch_it.dart';

class UserAuthPage extends StatefulWidget {
  final String? configMinAppVersion;
  final bool isUserLoggingOut;
  final bool isUserDeletingAccount;
  final bool createLinkedTipper;
  final String googleClientId;

  const UserAuthPage(this.configMinAppVersion,
      {super.key,
      this.isUserLoggingOut = false,
      this.isUserDeletingAccount = false,
      required this.createLinkedTipper,
      required this.googleClientId});

  @override
  UserAuthPageState createState() => UserAuthPageState();
}

class UserAuthPageState extends State<UserAuthPage> {
  final PackageInfoService packageInfoService =
      GetIt.instance<PackageInfoService>();

  @override
  void initState() {
    super.initState();
  }

  Future<bool> isClientVersionOutOfDate() async {
    if (widget.configMinAppVersion == null) {
      return false;
    }
    PackageInfo packageInfo = await packageInfoService.packageInfo;

    List<String> currentVersionParts = packageInfo.version.split('.');
    List<String> newVersionParts = widget.configMinAppVersion!.split('.');

    for (int i = 0; i < newVersionParts.length; i++) {
      int currentPart = int.parse(currentVersionParts[i]);
      int newPart = int.parse(newVersionParts[i]);

      if (newPart > currentPart) {
        return true;
      } else if (newPart < currentPart) {
        return false;
      }
    }

    return false;
  }

  Future<bool> _linkUserToTipper() async {
    User? authenticatedFirebaseUser = FirebaseAuth.instance.currentUser;
    if (authenticatedFirebaseUser == null) {
      return false;
    }
    TippersViewModel tippersViewModel = di<TippersViewModel>();
    return await tippersViewModel.linkUserToTipper();
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void _initializeFirebaseMessagingService() {
    if (!kIsWeb) {
      di.registerLazySingleton<FirebaseMessagingService>(
          () => FirebaseMessagingService());
      di<FirebaseMessagingService>().initializeFirebaseMessaging();
    }
  }

  @override
  Widget build(BuildContext context) {
    log('UserAuthPage.build()');
    if (widget.isUserLoggingOut) {
      signOut();
      log('UserAuthPage.build() - user signed out');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (BuildContext context) => const MyApp()),
          (Route<dynamic> route) => false,
        );
      });
    }
    if (widget.isUserDeletingAccount) {
      di<TippersViewModel>().deleteAccount();
      log('UserAuthPage.build() - user deleted account');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (BuildContext context) => const MyApp()),
          (Route<dynamic> route) => false,
        );
      });
    }

    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.hasData && authSnapshot.data != null) {
            _initializeFirebaseMessagingService();
          }

          return FutureBuilder<bool>(
            future: isClientVersionOutOfDate(),
            builder: (context, versionSnapshot) {
              if (versionSnapshot.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: League.afl.colour));
              }
              if (versionSnapshot.data == true) {
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
                    GoogleProvider(clientId: widget.googleClientId),
                    EmailAuthProvider(),
                  ],
                  headerBuilder: (context, constraints, shrinkOffset) {
                    return Padding(
                      padding: EdgeInsets.all(20),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(15.0),
                            child: Image.asset('assets/icon/AppIcon.png')),
                      ),
                    );
                  },
                  subtitleBuilder: (context, action) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: action == AuthAction.signIn
                          ? const Text(
                              'Welcome to DAU Footy Tipping. Sign in with your Apple or Google account to continue.\n\nOptionally, you can sign in with your email and password.')
                          : const Text(
                              'Welcome to DAU Footy Tipping, please register with your Apple or Google account before signing in.\n\nAlternatively, you can register with your email and password.'),
                    );
                  },
                  footerBuilder: (context, action) {
                    return FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'Loading...',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        } else if (snapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                              'If you\'re having trouble signing in, click here: https://interview.coach/tipping\n'
                              'App Version: Unknown',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        } else {
                          final packageInfo = snapshot.data!;
                          return Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              'If you\'re having trouble signing in, click here: https://interview.coach/tipping\n'
                              'App Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          );
                        }
                      },
                    );
                  },
                );
              }

              User? authenticatedFirebaseUser = authSnapshot.data;
              if (authenticatedFirebaseUser == null) {
                return const LoginErrorScreen(
                    errorMessage:
                        'No user context found. Please try signing in again.');
              }

              if (authenticatedFirebaseUser.isAnonymous) {
                return const LoginErrorScreen(
                    errorMessage:
                        'You have logged in as anonymous. This App does not support anonymous logins.');
              }
              if (authenticatedFirebaseUser.emailVerified == false) {
                authenticatedFirebaseUser.sendEmailVerification();

                return const LoginErrorScreen(
                    errorMessage:
                        'Your email is not verified. Please try checking your inbox and junk mail and verify your email first.');
              }

              FirebaseAnalytics.instance.logLogin(
                  loginMethod:
                      authenticatedFirebaseUser.providerData[0].providerId);

              return FutureBuilder<bool>(
                future: _linkUserToTipper(),
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
                    if (snapshot.data == false) {
                      return LoginErrorScreen(
                          errorMessage:
                              'No tipper record found for login: ${authenticatedFirebaseUser.email}.\n\nContact daufootytipping@gmail.com to have your login associated with your existing tipper record.');
                    }

                    return const HomePage();
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
  final bool displaySignOutButton;
  final String googleClientId;

  const LoginErrorScreen(
      {super.key,
      required this.errorMessage,
      this.displaySignOutButton = true,
      this.googleClientId = ''});

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
            if (displaySignOutButton)
              SizedBox(
                width: 150,
                child: displaySignOutButton
                    ? OutlinedButton(
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
                              builder: (context) => const UserAuthPage(
                                null,
                                isUserLoggingOut: true,
                                createLinkedTipper: false,
                                googleClientId: '',
                              ),
                            ),
                          );
                        },
                      )
                    : Container(),
              ),
          ],
        ),
      ),
    );
  }
}
