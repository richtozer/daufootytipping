import 'package:daufootytipping/pages/user_auth/auth_fade_route.dart';
import 'package:daufootytipping/pages/user_auth/user_auth.dart';
import 'package:daufootytipping/pages/user_auth/user_auth_background.dart';
import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:daufootytipping/widgets/app_content_width.dart';
import 'package:flutter/material.dart';
import 'package:daufootytipping/constants/paths.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Opens the support site in the browser (a new tab on the web). Returns whether it
/// could be opened.
Future<bool> openSupportSite(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

class LoginIssueScreen extends StatelessWidget {
  final String message;
  final bool displaySignOutButton;
  final String googleClientId;
  final Color msgColor;
  final VoidCallback? onRetry;

  /// Opens the support site. A parameter so a test does not launch a browser.
  final Future<bool> Function(Uri url) openUrl;

  /// The label of the button that opens the support site.
  static const String getHelpLabel = 'Get help';

  const LoginIssueScreen({
    super.key,
    required this.message,
    this.displaySignOutButton = true,
    this.googleClientId = '',
    this.msgColor = Colors.red,
    this.onRetry,
    this.openUrl = openSupportSite,
  });

  Future<void> _openSupport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await openUrl(Uri.parse(p.supportUrl));
    } on Object {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the support page. Please visit ${p.supportUrl}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UserAuthBackground(
        child: FormContentWidth(
          // Scrolls, so the buttons stay reachable on a short screen or in landscape.
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 50),
                  const Padding(padding: EdgeInsets.all(20), child: AppIcon()),
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
                  if (onRetry != null)
                    SizedBox(
                      width: 150,
                      child: OutlinedButton(
                        onPressed: onRetry,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Icon(Icons.refresh), Text('Retry')],
                        ),
                      ),
                    ),
                  if (onRetry != null && displaySignOutButton)
                    const SizedBox(height: 12),
                  if (displaySignOutButton)
                    SizedBox(
                      width: 150,
                      child: displaySignOutButton
                          ? OutlinedButton(
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.logout),
                                  Text('Sign Out'),
                                ],
                              ),
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  authFadeRoute(
                                    (context) => const UserAuthPage(
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
                  if (onRetry != null || displaySignOutButton)
                    const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 150),
                    child: OutlinedButton(
                      onPressed: () => _openSupport(context),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.help_outline),
                          SizedBox(width: 4),
                          Text(getHelpLabel),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
