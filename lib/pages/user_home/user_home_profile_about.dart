import 'package:daufootytipping/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

final List<Widget> aboutBoxChildren = <Widget>[
  const SizedBox(height: 24),
  const Text('Sponsored by The Interview Coach'),
];

Future<Widget> aboutDialog(BuildContext context) async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  String appName = packageInfo.appName;
  String version = packageInfo.version;
  String buildNumber = packageInfo.buildNumber;

  return OutlinedButton(
    child: const Text('About this application ...'),
    onPressed: () {
      showAboutDialog(
        context: context,
        applicationIcon: const AppIcon(size: 75),
        applicationName: appName,
        applicationVersion: '$version\nbuild $buildNumber',
        children: aboutBoxChildren,
      );
    },
  );
}
