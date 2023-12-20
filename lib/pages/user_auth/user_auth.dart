import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:daufootytipping/pages/user_auth/auth_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/tips_viewmodel.dart';
import 'package:daufootytipping/pages/user_home/user_home.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UserAuthPage extends StatelessWidget {
  static const String currentDAUComp =
      '-Nk88l-ww9pYF1j_jUq7'; //TODO remove hardcoding

  const UserAuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TippersViewModel>(
      create: (_) => TippersViewModel(),
      child: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            var clientId =
                "1008137398618-6mltcn1gj9p97p82ebar74gmrgasci97.apps.googleusercontent.com"; //TODO remove hardcoding
            return SignInScreen(
              providers: [
                EmailAuthProvider(),
                GoogleProvider(clientId: clientId),
              ],
              headerBuilder: (context, constraints, shrinkOffset) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Icon(Icons.sports_rugby),
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
                    'By signing in, you agree to our terms and conditions.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              },
            );
          }

          //once we pass signin we have a firebase auth user context
          User? user = snapshot.data;
          if (user == null) {
            throw Exception('No user context found');
          }
          if (user.isAnonymous) {
            throw Exception('User is anonymous');
          }
          if (user.emailVerified == false) {
            throw Exception('User email not verified');
          }

          FirebaseAnalytics.instance
              .logLogin(loginMethod: user.providerData[0].providerId);

          //at this point we have a verfied logged on user - as we send them
          //to the home page, make sure they are represented in the realtime database
          // as a tipper linked to their firebase auth record,
          //if not create a Tipper record for them.

          AuthViewModel authViewModel = AuthViewModel(user);

          return FutureBuilder<Tipper>(
            future: authViewModel.getCurrentTipper(),
            builder: (BuildContext context, AsyncSnapshot<Tipper> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator(); // or your own loading widget
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              } else {
                Tipper currentTipper = snapshot.data as Tipper;
                return Consumer<TippersViewModel>(
                  builder: (context, tippersViewModel, child) {
                    return ChangeNotifierProvider<TipsViewModel>(
                      create: (_) =>
                          TipsViewModel(currentTipper, currentDAUComp),
                      child: HomePage(currentTipper),
                    );
                  },
                );
              }
            },
          );
        },
      ),
    );
  }
}
