import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:daufootytipping/main.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_upgate_app_widget.dart';
import 'package:daufootytipping/services/firebase_messaging_service.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:daufootytipping/services/package_info_service.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    as sign_in_with_apple;
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isEmailAuthExpanded = false;
  bool _isPasswordResetMode = false;
  bool _isAuthInProgress = false;
  String? _socialAuthError;
  String? _emailAuthError;
  String? _emailAuthInfo;
  Future<void>? _googleSignInInitFuture;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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

  bool get _supportsAppleSignIn =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.android;

  Future<void> _ensureGoogleSignInInitialized() {
    _googleSignInInitFuture ??= GoogleSignIn.instance.initialize();
    return _googleSignInInitFuture!;
  }

  Future<void> _signInWithGoogle() async {
    if (_isAuthInProgress) {
      return;
    }
    setState(() {
      _isAuthInProgress = true;
      _socialAuthError = null;
    });

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        await _ensureGoogleSignInInitialized();
        final GoogleSignInAccount googleUser = await GoogleSignIn.instance
            .authenticate();
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;
        final String? idToken = googleAuth.idToken;
        if (idToken == null) {
          throw FirebaseAuthException(
            code: 'google-missing-id-token',
            message: 'Google sign-in did not return an ID token.',
          );
        }

        final OAuthCredential credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() {
          _socialAuthError = 'Google sign-in failed.';
        });
      }
    } on FirebaseAuthException catch (_) {
      setState(() {
        _socialAuthError = 'Google sign-in failed.';
      });
    } catch (_) {
      setState(() {
        _socialAuthError = 'Google sign-in failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthInProgress = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (_isAuthInProgress) {
      return;
    }
    setState(() {
      _isAuthInProgress = true;
      _socialAuthError = null;
    });

    try {
      if (kIsWeb) {
        final AppleAuthProvider provider = AppleAuthProvider();
        provider.addScope('email');
        provider.addScope('name');
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final AppleAuthProvider provider = AppleAuthProvider();
        provider.addScope('email');
        provider.addScope('name');
        await FirebaseAuth.instance.signInWithProvider(provider);
      } else {
        final String rawNonce = _generateNonce();
        final String nonce = _sha256OfString(rawNonce);
        final AuthorizationCredentialAppleID credential =
            await SignInWithApple.getAppleIDCredential(
              scopes: <AppleIDAuthorizationScopes>[
                AppleIDAuthorizationScopes.email,
                AppleIDAuthorizationScopes.fullName,
              ],
              nonce: nonce,
            );

        final String? identityToken = credential.identityToken;
        if (identityToken == null || identityToken.isEmpty) {
          throw FirebaseAuthException(
            code: 'missing-identity-token',
            message: 'Apple sign-in did not return an identity token.',
          );
        }

        final OAuthCredential oauthCredential =
            AppleAuthProvider.credentialWithIDToken(
              identityToken,
              rawNonce,
              AppleFullPersonName(
                givenName: credential.givenName,
                familyName: credential.familyName,
              ),
            );

        await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      log(
        'Apple sign-in SignInWithAppleAuthorizationException: code=${e.code}, message=${e.message}',
      );
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() {
          _socialAuthError = 'Apple sign-in failed.';
        });
      }
    } on FirebaseAuthException catch (e) {
      log(
        'Apple sign-in FirebaseAuthException: code=${e.code}, message=${e.message}',
      );
      setState(() {
        _socialAuthError = 'Apple sign-in failed.';
      });
    } catch (e, stackTrace) {
      log('Apple sign-in unexpected exception: $e', stackTrace: stackTrace);
      setState(() {
        _socialAuthError = 'Apple sign-in failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthInProgress = false;
        });
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const String charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final math.Random random = math.Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) {
    final List<int> bytes = utf8.encode(input);
    final Digest digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _mapEmailAuthException(
    FirebaseAuthException e, {
    required bool isRegisterMode,
  }) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return isRegisterMode
            ? 'Email/password registration is not enabled.'
            : 'Email/password sign-in is not enabled.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      default:
        return isRegisterMode
            ? 'Could not create your account. Please try again.'
            : 'Could not sign in. Please try again.';
    }
  }

  String _mapPasswordResetException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
        return 'No account was found for that email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'Password reset is not enabled for this project.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Failed to send password reset email.';
    }
  }

  Widget _buildGoogleAuthButton() {
    const double buttonHeight = 56;
    final double fontSize = buttonHeight * 0.43;
    final double iconSlotWidth = buttonHeight * (28 / 44);

    final Widget button = SizedBox(
      height: buttonHeight,
      child: ElevatedButton(
        onPressed: _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF5F6368),
          elevation: 3,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: iconSlotWidth,
              child: Center(
                child: Image.asset(
                  'assets/google_logo.png',
                  width: fontSize,
                  height: fontSize,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return CircleAvatar(
                      radius: fontSize / 2,
                      backgroundColor: Colors.white,
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: fontSize * 0.75,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4285F4),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Sign in with Google',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF5F6368),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: iconSlotWidth),
          ],
        ),
      ),
    );

    if (!_isAuthInProgress) {
      return button;
    }
    return Opacity(opacity: 0.6, child: IgnorePointer(child: button));
  }

  Widget _buildAppleAuthButton() {
    final Widget button = SizedBox(
      height: 56,
      child: SignInWithAppleButton(
        onPressed: _signInWithApple,
        text: 'Sign in with Apple',
        style: SignInWithAppleButtonStyle.black,
        iconAlignment: sign_in_with_apple.IconAlignment.left,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        height: 56,
      ),
    );

    if (!_isAuthInProgress) {
      return button;
    }
    return Opacity(opacity: 0.6, child: IgnorePointer(child: button));
  }

  Future<void> _signInOrRegisterWithEmail() async {
    if (_isAuthInProgress) {
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _emailAuthError = 'Email and password are required.';
        _emailAuthInfo = null;
      });
      return;
    }

    setState(() {
      _isAuthInProgress = true;
      _emailAuthError = null;
      _emailAuthInfo = null;
    });

    try {
      if (_isRegisterMode) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _emailAuthError = _mapEmailAuthException(
          e,
          isRegisterMode: _isRegisterMode,
        );
        _emailAuthInfo = null;
      });
    } catch (_) {
      setState(() {
        _emailAuthError = 'Email authentication failed.';
        _emailAuthInfo = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthInProgress = false;
        });
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _emailAuthError = 'Enter your email below to reset password.';
        _emailAuthInfo = null;
      });
      return;
    }

    setState(() {
      _isAuthInProgress = true;
      _emailAuthError = null;
      _emailAuthInfo = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() {
          _emailAuthInfo =
              'If an account exists for this email, a password reset link has been sent to your inbox.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'If an account exists for this email, a password reset link has been sent to your inbox.',
            ),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      log(
        'Password reset FirebaseAuthException: code=${e.code}, message=${e.message}',
      );
      setState(() {
        _emailAuthError = _mapPasswordResetException(e);
        _emailAuthInfo = null;
      });
    } catch (e, stackTrace) {
      log('Password reset unexpected exception: $e', stackTrace: stackTrace);
      setState(() {
        _emailAuthError = 'Could not send password reset email.';
        _emailAuthInfo = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthInProgress = false;
        });
      }
    }
  }

  Widget _buildSignInForm(BuildContext context) {
    final subtitle = _isRegisterMode
        ? 'Welcome to DAU Footy Tipping, please register with your Apple or Google account before signing in.'
        : 'Welcome to DAU Footy Tipping. Sign in with your Apple or Google account to continue.';
    final emailAuthDescription = _isRegisterMode
        ? 'Optionally, you can register with your email and password.'
        : _isPasswordResetMode
        ? 'Enter your email below and tap Reset to request a password reset link.'
        : 'Optionally, you can sign in with your email and password.';
    final emailAuthToggleText = _isEmailAuthExpanded
        ? 'Hide email sign-in options'
        : "Don't have an Apple or Google account? Click here to sign in with email.";
    final isPasswordResetMode = !_isRegisterMode && _isPasswordResetMode;
    final emailPrimaryActionText = _isRegisterMode
        ? 'Register'
        : isPasswordResetMode
        ? 'Reset'
        : 'Sign In';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15.0),
                  child: Image.asset(
                    'assets/icon/AppIcon.png',
                    height: 110,
                    width: 110,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(subtitle, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                if (_supportsAppleSignIn) ...[
                  _buildAppleAuthButton(),
                  const SizedBox(height: 8),
                ],
                _buildGoogleAuthButton(),
              ] else ...[
                _buildGoogleAuthButton(),
                if (_supportsAppleSignIn) ...[
                  const SizedBox(height: 8),
                  _buildAppleAuthButton(),
                ],
              ],
              if (_socialAuthError != null)
                Card(
                  color: Colors.red.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Text(
                      _socialAuthError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isAuthInProgress
                    ? null
                    : () {
                        setState(() {
                          _isEmailAuthExpanded = !_isEmailAuthExpanded;
                          _emailAuthError = null;
                          _emailAuthInfo = null;
                          _isPasswordResetMode = false;
                        });
                      },
                child: Text(emailAuthToggleText, textAlign: TextAlign.center),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _isEmailAuthExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(emailAuthDescription, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      autofillHints: const <String>[
                        AutofillHints.email,
                        AutofillHints.username,
                      ],
                      textInputAction: isPasswordResetMode
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) {
                        if (isPasswordResetMode) {
                          if (!_isAuthInProgress) {
                            _sendPasswordReset();
                          }
                        } else {
                          FocusScope.of(context).nextFocus();
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (!isPasswordResetMode) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        autofillHints: const <String>[AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isAuthInProgress) {
                            _signInOrRegisterWithEmail();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isAuthInProgress
                            ? null
                            : isPasswordResetMode
                            ? _sendPasswordReset
                            : _signInOrRegisterWithEmail,
                        child: Text(emailPrimaryActionText),
                      ),
                    ),
                    if (_emailAuthError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Card(
                          color: Colors.red.shade100,
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Text(
                              _emailAuthError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red.shade900),
                            ),
                          ),
                        ),
                      ),
                    if (_emailAuthInfo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Card(
                          color: const Color(0xFFE8F0FE),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Text(
                              _emailAuthInfo!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF1A73E8)),
                            ),
                          ),
                        ),
                      ),
                    if (!_isRegisterMode && !isPasswordResetMode)
                      TextButton(
                        onPressed: _isAuthInProgress
                            ? null
                            : () {
                                setState(() {
                                  _isPasswordResetMode = true;
                                  _emailAuthError = null;
                                  _emailAuthInfo = null;
                                });
                              },
                        child: const Text('Forgot password?'),
                      ),
                    if (!_isRegisterMode && isPasswordResetMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: _isAuthInProgress
                                ? null
                                : () {
                                    setState(() {
                                      _isPasswordResetMode = false;
                                      _emailAuthError = null;
                                      _emailAuthInfo = null;
                                    });
                                  },
                            child: Text(
                              'Back to sign in',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: _isAuthInProgress
                          ? null
                          : () {
                              setState(() {
                                _isRegisterMode = !_isRegisterMode;
                                _emailAuthError = null;
                                _emailAuthInfo = null;
                                _isPasswordResetMode = false;
                              });
                            },
                      child: Text(
                        _isRegisterMode
                            ? 'Already have an account? Sign in'
                            : 'Need an email account? Register',
                      ),
                    ),
                  ],
                ),
              ),
              if (kIsWeb)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: TextButton(
                    onPressed: _isAuthInProgress
                        ? null
                        : () async {
                            try {
                              await FirebaseAuth.instance.signInAnonymously();
                              log('Signed in anonymously via text link');
                            } catch (e) {
                              log(
                                'Error signing in anonymously via text link: $e',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Anonymous sign-in failed: ${e.toString()}',
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
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Loading...',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\nApp Version: Unknown',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    );
                  } else {
                    final packageInfo = snapshot.data!;
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\nApp Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
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
                return _buildSignInForm(context);
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
