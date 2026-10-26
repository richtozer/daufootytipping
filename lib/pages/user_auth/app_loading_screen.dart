import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:flutter/material.dart';

/// The spinner shown while the app starts and while sign-in is checked, on the
/// same veiled backdrop as the screens either side of it.
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return UserAuthBackground(
      child: Center(child: CircularProgressIndicator(color: League.afl.colour)),
    );
  }
}
