import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:flutter/material.dart';

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
              child: AppIcon(),
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
