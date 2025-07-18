import 'dart:developer';
import 'package:daufootytipping/main.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_upgate_app_widget.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart' as firebase_ui_auth;
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

  const UserAuthPage(
    this.configMinAppVersion, {
    super.key,
    this.isUserLoggingOut = false,
    this.isUserDeletingAccount = false,
    required this.createLinkedTipper,
    required this.googleClientId,
  });

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

    //use this opportunity to setup default analytics parameter for version
    if (!kIsWeb) {
      FirebaseAnalytics.instance.setDefaultEventParameters({
        'version': packageInfo.version,
      });
    }

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

  Future<Tipper?> _linkUserToTipper() async {
    User? authenticatedFirebaseUser = FirebaseAuth.instance.currentUser;
    if (authenticatedFirebaseUser == null) {
      return null;
    }
    TippersViewModel tippersViewModel = di<TippersViewModel>();
    return await tippersViewModel.findExistingTipper();
  }

  Future<bool> _updateOrCreateTipper(String? name, Tipper? tipper) async {
    TippersViewModel tippersViewModel = di<TippersViewModel>();
    return await tippersViewModel.updateOrCreateTipper(name, tipper);
  }

  void signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void _initializeFirebaseMessagingService() {
    if (!kIsWeb) {
      di.registerLazySingleton<FirebaseMessagingService>(
        () => FirebaseMessagingService(),
      );
      di<FirebaseMessagingService>().initializeFirebaseMessaging();
    }
  }

  void _showEditNameDialog(BuildContext context, Tipper? tipper) {
    final TextEditingController nameController = TextEditingController(
      text: tipper?.name,
    );
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing the dialog without saving
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('New Tipper Alias'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome to the competition. You need to choose a tipper alias. This is your identity as shown to others in the competition. It must be unique.',
                  ),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Alias',
                      hintText: 'Enter a name e.g. The Oracle',
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    String newName = nameController.text.trim();
                    if (newName.isEmpty) {
                      setState(() {
                        errorMessage = 'Alias cannot be empty.';
                      });
                      return;
                    }
                    if (newName.length < 2) {
                      setState(() {
                        errorMessage =
                            'Alias must be at least 2 characters long.';
                      });
                      return;
                    }
                    try {
                      // Create and link the new tipper
                      bool res = await _updateOrCreateTipper(newName, tipper);

                      if (res) {
                        if (context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => const HomePage(),
                            ),
                          );
                        }
                      } else {
                        setState(() {
                          errorMessage = 'Failed to create or update tipper.';
                        });
                      }
                    } catch (e) {
                      setState(() {
                        errorMessage = 'Error: $e';
                      });
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
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
      di<TippersViewModel>().deleteAccount().then((result) {
        if (result == null) {
          log('UserAuthPage.build() - user deleted account');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (BuildContext context) => const MyApp(),
              ),
              (Route<dynamic> route) => false,
            );
          });
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result)));
          }
        }
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
                  child: CircularProgressIndicator(color: Colors.orange),
                );
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
                            //color: Colors.white10,
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  Text(
                                    "This version of the app is no longer supported, please update the app from the app store.",
                                    //style: TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(10.0),
                                    child: UpdateAppLink(),
                                  ),
                                ],
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
                    GoogleProvider(clientId: widget.googleClientId),
                    AppleProvider(),
                    //firebase_ui_auth.PhoneAuthProvider(),
                    firebase_ui_auth.EmailAuthProvider(),
                    // firebase_ui_auth.AnonymousAuthProvider(), // Removed this line
                  ],
                  headerBuilder: (context, constraints, shrinkOffset) {
                    return Padding(
                      padding: EdgeInsets.all(20),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15.0),
                          child: Image.asset('assets/icon/AppIcon.png'),
                        ),
                      ),
                    );
                  },
                  subtitleBuilder: (context, action) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: action == AuthAction.signIn
                          ? const Text(
                              'Welcome to DAU Footy Tipping. Sign in with your Apple or Google account to continue.\n\nOptionally, you can sign in with your email and password.',
                            )
                          : const Text(
                              'Welcome to DAU Footy Tipping, please register with your Apple or Google account before signing in.\n\nAlternatively, you can register with your email and password.',
                            ),
                    );
                  },
                  footerBuilder: (context, action) {
                    return Column(
                      // Wrapped in Column
                      children: [
                        if (kIsWeb) //TODO hack - remove
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextButton(
                              onPressed: () async {
                                try {
                                  await FirebaseAuth.instance
                                      .signInAnonymously();
                                  log("Signed in anonymously via text link");
                                } catch (e) {
                                  log(
                                    "Error signing in anonymously via text link: $e",
                                  );
                                  if (context.mounted) {
                                    // Ensure widget is still in tree
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "Anonymous sign-in failed: ${e.toString()}",
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                'Click here to view Stats',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary, // Or a specific blue
                                ),
                              ),
                            ),
                          ),
                        FutureBuilder<PackageInfo>(
                          // Original footer content
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
                                  'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\n'
                                  'App Version: Unknown',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              );
                            } else {
                              final packageInfo = snapshot.data!;
                              return Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\n'
                                  'App Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    );
                  },
                );
              }

              User? authenticatedFirebaseUser = authSnapshot.data;
              if (authenticatedFirebaseUser == null) {
                return const LoginIssueScreen(
                  message:
                      'No user context found. Please try signing in again.',
                );
              }

              if (authenticatedFirebaseUser.emailVerified == false &&
                  !authenticatedFirebaseUser.isAnonymous) {
                // Also check for non-anonymous user
                authenticatedFirebaseUser.sendEmailVerification();

                return const LoginIssueScreen(
                  message:
                      'Your email is not verified. Please check your inbox or junk/spam and verify your email first. Then try log in again',
                  msgColor: Colors.green,
                );
              }

              FirebaseAnalytics.instance.logLogin(
                loginMethod: authenticatedFirebaseUser.providerData.isNotEmpty
                    ? authenticatedFirebaseUser.providerData[0].providerId
                    : 'unknown',
              );

              return FutureBuilder<Tipper?>(
                future: _linkUserToTipper(),
                builder: (BuildContext context, AsyncSnapshot<Tipper?> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: Colors.orange),
                    );
                  } else if (snapshot.hasError) {
                    return LoginIssueScreen(
                      message:
                          'Unexpected error ${snapshot.error}. Contact support: https://interview.coach/tipping',
                    );
                  } else if (snapshot.data == null) {
                    // This means no existing Tipper record
                    if (authenticatedFirebaseUser.isAnonymous) {
                      // For new anonymous users, bypass edit name dialog
                      return FutureBuilder<bool>(
                        future: _updateOrCreateTipper(
                          null,
                          null,
                        ), // Pass null to let ViewModel handle name
                        builder: (BuildContext context, AsyncSnapshot<bool> updateSnapshot) {
                          if (updateSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                color: Colors.orange,
                              ),
                            );
                          } else if (updateSnapshot.hasError) {
                            return LoginIssueScreen(
                              message:
                                  'Error creating anonymous user: ${updateSnapshot.error}. Contact support.',
                            );
                          } else if (updateSnapshot.data == false) {
                            return LoginIssueScreen(
                              message:
                                  'Failed to create anonymous user. Contact support.',
                            );
                          } else {
                            // Successfully created anonymous user, navigate to home
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => const HomePage(),
                                ),
                              );
                            });
                            return Container(); // Show loading or empty container while navigating
                          }
                        },
                      );
                    } else {
                      // For new non-anonymous users, show edit name dialog as before
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _showEditNameDialog(context, null);
                      });
                      return Container(); // Return an empty container while waiting for user input
                    }
                  } else {
                    // Existing tipper found
                    return FutureBuilder<bool>(
                      future: _updateOrCreateTipper(
                        snapshot.data!.name,
                        snapshot.data!,
                      ),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<bool> updateSnapshot,
                          ) {
                            if (updateSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: Colors.orange,
                                ),
                              );
                            } else if (updateSnapshot.hasError) {
                              return LoginIssueScreen(
                                message:
                                    'Unexpected error ${updateSnapshot.error}. Contact support: https://interview.coach/tipping',
                              );
                            } else if (updateSnapshot.data == false) {
                              return LoginIssueScreen(
                                message:
                                    'Failed to create or update tipper. Contact support: https://interview.coach/tipping',
                              );
                            } else {
                              return const HomePage();
                            }
                          },
                    );
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

class LoginIssueScreen extends StatelessWidget {
  final String message;
  final bool displaySignOutButton;
  final String googleClientId;
  final Color msgColor;

  const LoginIssueScreen({
    super.key,
    required this.message,
    this.displaySignOutButton = true,
    this.googleClientId = '',
    this.msgColor = Colors.red,
  });

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
                  color: msgColor,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      message,
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
                          children: [Icon(Icons.logout), Text('Sign Out')],
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
