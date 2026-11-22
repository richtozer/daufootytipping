import 'package:daufootytipping/platform/reload_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String appStoreUrl =
    'https://apps.apple.com/us/app/dau-footy-tipping/id6474896103';
const String playStoreUrl =
    'https://play.google.com/store/apps/details?id=coach.interview.daufootytipping';

/// Where the app is updated on [platform], or null where there is no store.
Uri? storeUrlFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => Uri.parse(appStoreUrl),
  TargetPlatform.android => Uri.parse(playStoreUrl),
  _ => null,
};

/// What a user of a version that is no longer supported is told, and how to
/// recover: a web page is updated by reloading it, an installed app from its
/// store.
String unsupportedVersionMessage({required bool onWeb}) => onWeb
    ? 'This version of the app is no longer supported. Reload the page to get '
          'the latest version. If you still see this notice, close the tab and '
          'reopen the site.'
    : 'This version of the app is no longer supported, please update the app '
          'from the app store.';

/// Says that this version is no longer supported and how to update it.
class UnsupportedVersionMessage extends StatelessWidget {
  const UnsupportedVersionMessage({super.key, this.onWeb = kIsWeb});

  /// Whether this is the web app. Only tests set it.
  final bool onWeb;

  @override
  Widget build(BuildContext context) => Text(
    unsupportedVersionMessage(onWeb: onWeb),
    textAlign: TextAlign.center,
  );
}

Future<bool> _openInBrowserOrStore(Uri url) async =>
    await canLaunchUrl(url) && await launchUrl(url);

/// The recovery button on the notice for a version that is no longer supported:
/// reloads the page on the web, opens the store on iOS and Android.
class UpdateAppLink extends StatelessWidget {
  const UpdateAppLink({
    super.key,
    this.onWeb = kIsWeb,
    this.platform,
    this.reload = reloadPage,
    this.open = _openInBrowserOrStore,
  });

  /// Whether this is the web app. Only tests set it.
  final bool onWeb;

  /// The platform to update on; the running one if null. Only tests set it.
  final TargetPlatform? platform;

  final Future<void> Function() reload;
  final Future<bool> Function(Uri url) open;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _update(context),
      child: Text(onWeb ? 'Reload' : 'Update App'),
    );
  }

  Future<void> _update(BuildContext context) async {
    if (onWeb) {
      await reload();
      return;
    }
    final Uri? store = storeUrlFor(platform ?? defaultTargetPlatform);
    final bool opened = store != null && await open(store);
    if (opened || !context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the app store. Search for DAU Footy Tipping in your '
          'app store to update.',
        ),
      ),
    );
  }
}
