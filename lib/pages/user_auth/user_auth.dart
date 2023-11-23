import 'package:daufootytipping/pages/user_auth/user_auth_model.dart';
import 'package:flutter/material.dart';

class UserAuthPage extends StatelessWidget {
  static const String route = '/Auth';
  final AuthViewModel authViewModel;

  const UserAuthPage(this.authViewModel, {super.key});

  Future<void> _signIn(BuildContext context) async {
    await authViewModel.signIn();
    // TODO: navigate to home page
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DAU Footy Tipping'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'DAU Footy Tipping.',
              textAlign: TextAlign.center,
            ),
            const Text(
              'Sign in to get started.',
              textAlign: TextAlign.center,
            ),
            if (authViewModel.signingIn) ...const <Widget>[
              SizedBox(
                height: 32,
              ),
              Center(child: CircularProgressIndicator()),
            ],
            const Expanded(
              child: SizedBox(
                height: 32,
              ),
            ),
            ElevatedButton(
              onPressed: authViewModel.signingIn
                  ? null
                  : () async {
                      await _signIn(context);
                    },
              child: const Text('Sign in with Auth0'),
            ),
          ],
        ),
      ),
    );
  }
}
