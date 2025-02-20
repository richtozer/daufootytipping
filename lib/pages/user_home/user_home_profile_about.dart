import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

final List<Widget> aboutBoxChildren = <Widget>[
  const SizedBox(height: 24),
  const Text('Sponsored by The InterView Coach')
];

Future<Widget> aboutDialog(context) async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  String appName = packageInfo.appName;
  String version = packageInfo.version;
  String buildNumber = packageInfo.buildNumber;

  return OutlinedButton(
    child: const Text('About this application ...'),
    onPressed: () {
      showAboutDialog(
        context: context,
        applicationIcon: ClipRRect(
          borderRadius: BorderRadius.circular(15.0),
          child: SizedBox(
            width: 75.0, // Set the width
            height: 75.0, // Set the height
            child: Image.asset('assets/icon/AppIcon.png'),
          ),
        ),
        applicationName: appName,
        applicationVersion: '$version\nbuild $buildNumber',
        children: aboutBoxChildren,
      );
    },
  );
}
