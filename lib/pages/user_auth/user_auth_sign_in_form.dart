import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide IconAlignment;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class UserAuthSignInForm extends StatefulWidget {
  final String googleClientId;

  const UserAuthSignInForm({super.key, required this.googleClientId});

  @override
  State<UserAuthSignInForm> createState() => _UserAuthSignInFormState();
}

class _UserAuthSignInFormState extends State<UserAuthSignInForm> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isEmailAuthExpanded = false;
  bool _isPasswordResetMode = false;
  bool _isHelpExpanded = false;
  bool _isAuthInProgress = false;
  String? _socialAuthError;
  String? _emailAuthError;
  String? _emailAuthInfo;
  Future<void>? _googleSignInInitFuture;

  bool get _supportsAppleSignIn =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

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
        iconAlignment: IconAlignment.left,
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
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

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
    final String email = _emailController.text.trim();
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

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color bodyTextColor = colorScheme.onSurface;
    final Color footerTextColor = colorScheme.onSurface.withValues(alpha: 0.82);
    final Color inputTextColor = isDarkMode
        ? Colors.white
        : colorScheme.onSurface;
    final Color inputLabelColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.9)
        : colorScheme.onSurface.withValues(alpha: 0.76);
    final Color inputBorderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.55)
        : colorScheme.outline.withValues(alpha: 0.72);
    final Color inputFillColor = isDarkMode
        ? const Color(0xFF1E2A1F)
        : colorScheme.surface;
    final TextStyle inputTextStyle = TextStyle(color: inputTextColor);
    final TextStyle linkTextStyle = TextStyle(
      color: bodyTextColor,
      decoration: TextDecoration.underline,
    );
    final String subtitle = _isRegisterMode
        ? 'Welcome to DAU Footy Tipping, please register with your Apple or Google account before signing in.'
        : 'Welcome to DAU Footy Tipping. Sign in with your Apple or Google account to continue.';
    final String emailAuthDescription = _isRegisterMode
        ? 'Optionally, you can register with your email and password.'
        : _isPasswordResetMode
        ? 'Enter your email below and tap Reset to request a password reset link.'
        : 'Optionally, you can sign in with your email and password.';
    final String emailAuthToggleText = _isEmailAuthExpanded
        ? 'Hide email sign-in options'
        : "Don't have an Apple or Google account? Tap here to sign in with email.";
    final bool isPasswordResetMode = !_isRegisterMode && _isPasswordResetMode;
    final String emailPrimaryActionText = _isRegisterMode
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
              const Center(child: AppIcon()),
              const SizedBox(height: 20),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: bodyTextColor),
              ),
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
                child: Text(
                  emailAuthToggleText,
                  textAlign: TextAlign.center,
                  style: linkTextStyle,
                ),
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
                    Text(
                      emailAuthDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: bodyTextColor),
                    ),
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
                      style: inputTextStyle,
                      cursorColor: colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: 'Email',
                        hintStyle: TextStyle(color: inputLabelColor),
                        filled: true,
                        fillColor: inputFillColor,
                        border: const OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: inputBorderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 2,
                          ),
                        ),
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
                        style: inputTextStyle,
                        cursorColor: colorScheme.primary,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          hintStyle: TextStyle(color: inputLabelColor),
                          filled: true,
                          fillColor: inputFillColor,
                          border: const OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: inputBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
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
                        child: Text('Forgot password?', style: linkTextStyle),
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
                                color: bodyTextColor,
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
                        style: linkTextStyle,
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
                      'Tap here to view Stats',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: bodyTextColor,
                      ),
                    ),
                  ),
                ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isHelpExpanded = !_isHelpExpanded;
                  });
                },
                child: Text('Need help? Tap here.', style: linkTextStyle),
              ),
              if (_isHelpExpanded)
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Loading...',
                          style: TextStyle(color: footerTextColor),
                          textAlign: TextAlign.center,
                        ),
                      );
                    } else if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\nApp Version: Unknown',
                          style: TextStyle(color: footerTextColor),
                          textAlign: TextAlign.center,
                        ),
                      );
                    } else {
                      final PackageInfo packageInfo = snapshot.data!;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'If you\'re having trouble signing in, visit this site: https://interview.coach/tipping\nApp Version: ${packageInfo.version} (Build ${packageInfo.buildNumber})',
                          style: TextStyle(color: footerTextColor),
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
}
