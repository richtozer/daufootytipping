import 'package:flutter/material.dart';

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

Widget aboutDialog(context) {
  return ElevatedButton(
    child: const Text('About this application'),
    onPressed: () {
      showAboutDialog(
        context: context,
        applicationIcon: const FlutterLogo(),
        applicationName: 'DAU Footy Tipping',
        applicationVersion: 'January 2024',
        applicationLegalese: '\u{a9} 2024 The DAU Footy Tipping Authors',
        children: aboutBoxChildren,
      );
    },
  );
}
