import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<Widget> faq(BuildContext context) async {
  return OutlinedButton(
    child: const Text('FAQ ...'),
    onPressed: () {
      _launchURL();
    },
  );
}

Future<void> _launchURL() async {
  const urlString =
      'https://docs.google.com/document/d/e/2PACX-1vRAHQvWC-CvaeAVa7rPh7YCZAWb5nbzn7oOBt_qbyeXh4HWg96srmig13tz86h0PgOLGP9YnqGElRwk/pub';
  final url = Uri.parse(urlString);

  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  } else {
    throw 'Could not launch $urlString';
  }
}
