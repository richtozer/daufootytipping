import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<Widget> help(context) async {
  return OutlinedButton(
    child: const Text('Help ...'),
    onPressed: () {
      _launchURL();
    },
  );
}

Future<void> _launchURL() async {
  const urlString =
      'https://docs.google.com/document/d/e/2PACX-1vTOEzPdzyfKuDJJoyPz5ge4Z-dlwFQUNBilzguZZloxCqvKNp214Pp_-bxWTFY_MPmit1iZrhUQKpzm/pub';

  final url = Uri.parse(urlString);

  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  } else {
    throw 'Could not launch $urlString';
  }
}
