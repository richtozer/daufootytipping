import 'dart:convert';
import 'dart:developer';

import 'package:daufootytipping/main.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_login_issue_screen.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_sign_in_form.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_upgate_app_widget.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _isExitActionStarted = false;
  String? _exitActionError;
  Future<bool>? _clientVersionOutOfDateFuture;
  Future<Tipper?>? _existingTipperFuture;
  Future<bool>? _linkOrCreateTipperFuture;
  String? _authFlowUid;
  String? _linkOrCreateTipperKey;
  bool _newTipperDialogShown = false;

  @override
  void initState() {
    super.initState();
    _clientVersionOutOfDateFuture = isClientVersionOutOfDate();
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

  static const String _cachedTipperKey = 'cached_tipper';

  Future<Tipper?> _linkUserToTipper() async {
    User? authenticatedFirebaseUser = FirebaseAuth.instance.currentUser;
    if (authenticatedFirebaseUser == null) {
      return null;
    }

    // Fast path: return cached tipper if uid matches, so the
    // FutureBuilder resolves instantly on jetsam restarts.
    final Tipper? cached = await _loadCachedTipper(
      authenticatedFirebaseUser.uid,
    );
    if (cached != null) {
      log('UserAuthPage: using cached tipper ${cached.name}');
      return cached;
    }

    TippersViewModel tippersViewModel = di<TippersViewModel>();
    return await tippersViewModel.findExistingTipper();
  }

  Future<Tipper?> _loadCachedTipper(String currentUid) async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      final String? json = prefs.getString(_cachedTipperKey);
      if (json == null) return null;

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(
            jsonDecode(json) as Map,
          );
      if (data['authuid'] != currentUid) return null;

      return Tipper.fromCacheJson(data);
    } catch (e) {
      log('UserAuthPage: failed to load cached tipper: $e');
      return null;
    }
  }

  Future<void> _saveCachedTipper(Tipper tipper) async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setString(
        _cachedTipperKey,
        jsonEncode(tipper.toCacheJson()),
      );
    } catch (e) {
      log('UserAuthPage: failed to cache tipper: $e');
    }
  }

  Future<void> _clearCachedTipper() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.remove(_cachedTipperKey);
    } catch (e) {
      log('UserAuthPage: failed to clear cached tipper: $e');
    }
  }

  Future<bool> _updateOrCreateTipper(String? name, Tipper? tipper) async {
    TippersViewModel tippersViewModel = di<TippersViewModel>();
    return await tippersViewModel.updateOrCreateTipper(name, tipper);
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void _resetAuthFlowFutures() {
    _existingTipperFuture = null;
    _linkOrCreateTipperFuture = null;
    _authFlowUid = null;
    _linkOrCreateTipperKey = null;
    _newTipperDialogShown = false;
    _clearCachedTipper();
  }

  void _ensureAuthFlowForUser(User authenticatedFirebaseUser) {
    if (_authFlowUid != authenticatedFirebaseUser.uid) {
      _existingTipperFuture = null;
      _linkOrCreateTipperFuture = null;
      _linkOrCreateTipperKey = null;
      _newTipperDialogShown = false;
      _authFlowUid = authenticatedFirebaseUser.uid;
      StartupProfiling.instant(
        'startup.auth_state_authenticated',
        arguments: <String, Object?>{
          'isAnonymous': authenticatedFirebaseUser.isAnonymous,
        },
      );
    }
    _existingTipperFuture ??= StartupProfiling.trackAsync(
      'startup.link_user_to_tipper',
      _linkUserToTipper,
      arguments: <String, Object?>{
        'isAnonymous': authenticatedFirebaseUser.isAnonymous,
      },
    );
  }

  Future<bool> _ensureLinkOrCreateTipperFuture({
    required String key,
    required String? name,
    required Tipper? tipper,
  }) {
    if (_linkOrCreateTipperFuture == null || _linkOrCreateTipperKey != key) {
      _linkOrCreateTipperKey = key;
      _linkOrCreateTipperFuture = StartupProfiling.trackAsync(
        'startup.update_or_create_tipper',
        () => _updateOrCreateTipper(name, tipper),
        arguments: <String, Object?>{
          'hasExistingTipper': tipper != null,
        },
      );
    }
    return _linkOrCreateTipperFuture!;
  }

  void _navigateToAppRoot() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (BuildContext context) => const MyApp()),
        (Route<dynamic> route) => false,
      );
    });
  }

  Future<void> _startExitActionIfNeeded() async {
    if (_isExitActionStarted) {
      return;
    }
    _isExitActionStarted = true;

    if (widget.isUserLoggingOut) {
      try {
        await signOut();
        log('UserAuthPage - user signed out');
        _navigateToAppRoot();
      } catch (e) {
        log('UserAuthPage - sign out failed: $e');
        if (mounted) {
          setState(() {
            _exitActionError = 'Sign out failed. Please try again.';
          });
        }
      }
      return;
    }

    if (widget.isUserDeletingAccount) {
      final result = await di<TippersViewModel>().deleteAccount();
      if (result == null) {
        log('UserAuthPage - user deleted account');
        _navigateToAppRoot();
      } else if (mounted) {
        setState(() {
          _exitActionError = result;
        });
      }
    }
  }

  void _initializeFirebaseMessagingService() {
    if (!kIsWeb) {
      if (!di.isRegistered<FirebaseMessagingService>()) {
        di.registerLazySingleton<FirebaseMessagingService>(
          () => FirebaseMessagingService(),
        );
      }
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
                    'Welcome! To get started, pick a unique tipper alias. '
                    'This is the name other players will see you as in the '
                    'competition.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Tipper Alias',
                      hintText: 'e.g. The Oracle',
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
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await FirebaseAuth.instance.signOut();
                  },
                  child: const Text('Cancel'),
                ),
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
                        errorMessage = '$e';
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
    if (widget.isUserLoggingOut || widget.isUserDeletingAccount) {
      _startExitActionIfNeeded();

      if (_exitActionError != null) {
        return LoginIssueScreen(
          message: _exitActionError!,
          displaySignOutButton: false,
        );
      }

      return const _AuthLoadingScreen();
    }

    return Scaffold(
      body: UserAuthBackground(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          initialData: FirebaseAuth.instance.currentUser,
          builder: (context, authSnapshot) {
            final User? authenticatedFirebaseUser =
                authSnapshot.data ?? FirebaseAuth.instance.currentUser;
            if (authenticatedFirebaseUser == null) {
              _resetAuthFlowFutures();
            } else {
              _ensureAuthFlowForUser(authenticatedFirebaseUser);
              _initializeFirebaseMessagingService();
            }

            return FutureBuilder<bool>(
              future: _clientVersionOutOfDateFuture,
              builder: (context, versionSnapshot) {
                if (versionSnapshot.data == true) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(height: 50),
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: AppIcon(),
                        ),
                        SizedBox(height: 20),
                        SizedBox(
                          width: 300,
                          child: Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Column(
                                  children: [
                                    Text(
                                      "This version of the app is no longer supported, please update the app from the app store.",
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
                if (authenticatedFirebaseUser == null &&
                    authSnapshot.connectionState == ConnectionState.waiting) {
                  return const _AuthLoadingScreen();
                }
                if (!authSnapshot.hasData) {
                  return UserAuthSignInForm(
                    googleClientId: widget.googleClientId,
                  );
                }

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
                  future: _existingTipperFuture,
                  builder:
                      (
                        BuildContext context,
                        AsyncSnapshot<Tipper?> snapshot,
                      ) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const _AuthLoadingScreen();
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
                              future: _ensureLinkOrCreateTipperFuture(
                                key: 'anonymous-user',
                                name: null,
                                tipper: null,
                              ),
                              builder:
                                  (
                                    BuildContext context,
                                    AsyncSnapshot<bool> updateSnapshot,
                                  ) {
                                    if (updateSnapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const _AuthLoadingScreen();
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
                                      // Successfully created anonymous user
                                      return const HomePage();
                                    }
                                  },
                            );
                          } else {
                            // For new non-anonymous users, show edit name dialog as before
                            if (!_newTipperDialogShown) {
                              _newTipperDialogShown = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _showEditNameDialog(context, null);
                              });
                            }
                            return Container(); // Return an empty container while waiting for user input
                          }
                        } else {
                          // Existing tipper found — set the authenticated tipper
                          // immediately so HomePage can render without waiting for
                          // the background DB metadata update to complete.
                          final Tipper existingTipper = snapshot.data!;
                          di<TippersViewModel>().setAuthenticatedTipper(
                            existingTipper,
                          );
                          _saveCachedTipper(existingTipper);
                          _ensureLinkOrCreateTipperFuture(
                            key: existingTipper.dbkey ?? existingTipper.authuid,
                            name: existingTipper.name,
                            tipper: existingTipper,
                          ).catchError((Object e) {
                            log('Background tipper update failed: $e');
                            return false;
                          }).ignore();
                          return const HomePage();
                        }
                      },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const UserAuthBackground(
      overlayColor: Colors.transparent,
      child: Center(
        child: CircularProgressIndicator(color: Colors.orange),
      ),
    );
  }
}
