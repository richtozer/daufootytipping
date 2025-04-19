import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

class UpdateAppLink extends StatelessWidget {
  const UpdateAppLink({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _launchAppStore,
      child: Text('Update App'),
    );
  }

  void _launchAppStore() async {
    final Uri url = Uri.parse(getAppStoreUrl());
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      throw 'Could not launch ${url.toString()}';
    }
  }

  String getAppStoreUrl() {
    if (Platform.isIOS) {
      return 'https://apps.apple.com/us/app/dau-footy-tipping/id6474896103';
    } else if (Platform.isAndroid) {
      return 'https://play.google.com/store/apps/details?id=coach.interview.daufootytipping';
    } else {
      return '';
    }
  }
}
