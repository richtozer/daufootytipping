import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

final List<Widget> aboutBoxChildren = <Widget>[
  const SizedBox(height: 24),
  RichText(
    text: const TextSpan(
      children: <TextSpan>[
        TextSpan(
            text: "Flutter is Google's UI toolkit for building beautiful, "
                'natively compiled applications for mobile, web, and desktop '
                'from a single codebase. Learn more about Flutter at '),
        TextSpan(text: 'https://flutter.dev'),
        TextSpan(text: '.'),
      ],
    ),
  ),
];

Future<Widget> aboutDialog(context) async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();

  String appName = packageInfo.appName;
  String packageName = packageInfo.packageName;
  String version = packageInfo.version;
  String buildNumber = packageInfo.buildNumber;

  return ElevatedButton(
    child: Text('About this application ... package $packageName'),
    onPressed: () {
      showAboutDialog(
        context: context,
        applicationIcon:
            Expanded(child: Image.asset('assets/icon/AppIcon.png')),
        applicationName: appName,
        applicationVersion: '$version - build $buildNumber',
        applicationLegalese: '\u{a9} 2024 The DAU Footy Tipping Authors',
        children: aboutBoxChildren,
      );
    },
  );
}
