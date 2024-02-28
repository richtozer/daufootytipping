import 'dart:developer';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';

import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
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
  UserAuthPage(
      this.currentDAUCompKey, this.remoteConfigService, this.firebaseService,
      {super.key});

  final String currentDAUCompKey;

  final RemoteConfigService remoteConfigService;
  final FirebaseService firebaseService;

  var clientId = dotenv.env['GOOGLE_CLIENT_ID']!;

  PackageInfoService packageInfoService = GetIt.instance<PackageInfoService>();

  Future<bool> isClientVersionOutOfDate() async {
    PackageInfo packageInfo = await packageInfoService.packageInfo;

    List<String> currentVersionParts = packageInfo.version.split('.');
    String minAppVersion = await remoteConfigService.getConfigMinAppVersion();
    List<String> newVersionParts = minAppVersion.split('.');

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

  @override
  Widget build(BuildContext context) {
    log('UserAuthPage.build()');
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // check if the current app version is lower than the value set in
          // remote config, if so, force the user to update the app
          return FutureBuilder<bool>(
            future: isClientVersionOutOfDate(),
            builder: (context, versionSnapshot) {
              if (versionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (versionSnapshot.hasError) {
                return Text('Error: ${versionSnapshot.error}');
              } else if (versionSnapshot.data == true) {
                return const Center(
                    child: Text(
                  "This version of the app is no longer supported, please update the app from the app store.",
                ));
              }
              if (!snapshot.hasData) {
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
              User? authenticatedFirebaseUser = snapshot.data;
              if (authenticatedFirebaseUser == null) {
                throw Exception('No user context found');
              }
              if (authenticatedFirebaseUser.isAnonymous) {
                throw Exception('User is anonymous');
              }
              if (authenticatedFirebaseUser.emailVerified == false) {
                throw Exception('User email not verified');
              }

              FirebaseAnalytics.instance.logLogin(
                  loginMethod:
                      authenticatedFirebaseUser.providerData[0].providerId);

              //at this point we have a verfied logged on user - as we send them
              //to the home page, make sure they are represented in the realtime database
              // as a tipper linked to their firebase auth record,
              //if not create a Tipper record for them.

              TippersViewModel tippersViewModel = di<TippersViewModel>();

              return FutureBuilder<bool>(
                future: tippersViewModel.linkUserToTipper(),
                builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                  bool authenticatedUserIsLinkedToTipper =
                      snapshot.data ?? false;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child:
                            CircularProgressIndicator()); // or your own loading widget
                  } else if (snapshot.hasError) {
                    return ProfileScreen(
                      actions: [
                        DisplayNameChangedAction((context, oldName, newName) {
                          // TODO do something with the new name
                          throw UnimplementedError();
                        }),
                      ],
                      children: [
                        Container(
                          color: Colors.red,
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '${snapshot.error}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    );
                  } else {
                    if (!authenticatedUserIsLinkedToTipper) {
                      // default to the profile screen if no tipper record found
                      return ProfileScreen(
                        actions: [
                          DisplayNameChangedAction((context, oldName, newName) {
                            // TODO do something with the new name
                            throw UnimplementedError();
                          }),
                        ],
                        children: [
                          Container(
                            color: Colors.red,
                            padding: const EdgeInsets.all(8.0),
                            child: const Text(
                              'No Tipper record found, please contact the admin.',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      );
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
