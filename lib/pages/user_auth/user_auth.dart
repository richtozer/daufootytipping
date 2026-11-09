import 'dart:async';
import 'dart:developer';

import 'package:daufootytipping/pages/user_auth/user_auth_login_issue_screen.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_sign_in_form.dart';
import 'package:daufootytipping/pages/user_auth/app_loading_screen.dart';
import 'package:daufootytipping/pages/user_auth/app_root_navigator.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_upgate_app_widget.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/services/linked_tipper_resolver.dart';
import 'package:daufootytipping/services/tipper_link_service.dart';
import 'package:daufootytipping/services/app_badge_service.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:daufootytipping/services/startup_profiling.dart';
import 'package:daufootytipping/view_models/sign_in_link_controller.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  bool _isExitActionStarted = false;
  String? _exitActionError;
  Future<bool>? _clientVersionOutOfDateFuture;
  SignInLinkController? _linkController;
  String? _authFlowUid;
  bool _newTipperDialogShown = false;

  @override
  void initState() {
    super.initState();
    _clientVersionOutOfDateFuture = isClientVersionOutOfDate();
  }

  @override
  void dispose() {
    _linkController?.dispose();
    super.dispose();
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

  Future<void> signOut() async {
    if (!kIsWeb && di.isRegistered<FirebaseMessagingService>()) {
      await di<FirebaseMessagingService>().unregisterCurrentToken(
        tipperId: di<TippersViewModel>().authenticatedTipper?.dbkey,
      );
      await AppBadgeService().setCount(0);
    }
    await FirebaseAuth.instance.signOut();
  }

  void _resetAuthFlowFutures() {
    _linkController?.dispose();
    _linkController = null;
    _authFlowUid = null;
    _newTipperDialogShown = false;
    unawaited(di<TipperLinkService>().forget());
  }

  /// Starts linking the signed-in account to its tipper, once per account, after the
  /// account has passed the email check. The decisions are the controller's (see
  /// [SignInLinkController]); the page only draws its phase.
  void _ensureLinkControllerForUser(User user) {
    if (_authFlowUid != user.uid) {
      _linkController?.dispose();
      _linkController = null;
      _newTipperDialogShown = false;
      _authFlowUid = user.uid;
      StartupProfiling.instant(
        'startup.auth_state_authenticated',
        arguments: <String, Object?>{'isAnonymous': user.isAnonymous},
      );
    }
    if (_linkController != null) {
      return;
    }
    final account = LinkAccount(
      uid: user.uid,
      isAnonymous: user.isAnonymous,
      photoUrl: user.photoURL,
    );
    final controller = SignInLinkController(
      service: di<TipperLinkService>(),
      adoptTipper: (tipper) =>
          di<TippersViewModel>().setAuthenticatedTipper(tipper),
      syncPhoto: (photoUrl) => di<TippersViewModel>().updateOwnPhoto(photoUrl),
      canCreateTippers: di<TippersViewModel>().canCreateTippers,
    );
    _linkController = controller;
    unawaited(
      StartupProfiling.trackAsync(
        'startup.link_user_to_tipper',
        () => controller.start(account),
        arguments: <String, Object?>{'isAnonymous': user.isAnonymous},
      ),
    );
  }

  void _navigateToAppRoot() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      di<AppRootNavigator>().returnToRoot();
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

  void _showEditNameDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
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
                    'This is the name other tippers will see you as in the '
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
                    await signOut();
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
                      // Ask the server to create the tipper with this alias. On
                      // success the page moves on by itself; if the alias is not
                      // accepted, say why and stay here.
                      final bool created = await _linkController!.submitAlias(
                        newName,
                      );
                      if (created) {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } else {
                        setState(() {
                          errorMessage =
                              _linkController?.aliasError ??
                              'Failed to create tipper.';
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
    if (widget.isUserLoggingOut || widget.isUserDeletingAccount) {
      _startExitActionIfNeeded();

      if (_exitActionError != null) {
        return LoginIssueScreen(
          message: _exitActionError!,
          displaySignOutButton: false,
        );
      }

      return const AppLoadingScreen();
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
                        Padding(padding: EdgeInsets.all(20), child: AppIcon()),
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
                  return const AppLoadingScreen();
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
                    message: 'Your email is not verified. Please check your inbox or junk/spam and verify your email first. Then try log in again',
                    msgColor: Colors.green,
                  );
                }

                FirebaseAnalytics.instance.logLogin(
                  loginMethod: authenticatedFirebaseUser.providerData.isNotEmpty
                      ? authenticatedFirebaseUser.providerData[0].providerId
                      : 'unknown',
                );

                _ensureLinkControllerForUser(authenticatedFirebaseUser);
                return ListenableBuilder(
                  listenable: _linkController!,
                  builder: (context, _) => _buildForLinkPhase(context),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Draws where linking the account to its tipper has got to.
  Widget _buildForLinkPhase(BuildContext context) {
    final controller = _linkController!;
    switch (controller.phase) {
      case LinkPhase.resolving:
        return const AppLoadingScreen();
      case LinkPhase.ready:
        return const HomePage();
      case LinkPhase.needsAlias:
        // A new account: ask for the alias it will be known by, once.
        if (!_newTipperDialogShown) {
          _newTipperDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showEditNameDialog(context);
            }
          });
        }
        return Container();
      case LinkPhase.unavailable:
        return LoginIssueScreen(
          message:
              controller.message ??
              'Could not sign you in right now. Please try again.',
          onRetry: controller.retry,
        );
      case LinkPhase.refused:
        return LoginIssueScreen(
          message: controller.message ?? 'Something went wrong signing you in. Please try again. If it keeps happening, tap Get help.',
        );
    }
  }
}
