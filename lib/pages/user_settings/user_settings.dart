import 'package:daufootytipping/pages/admin_home/admin_home.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  static const String route = '/Settings';
  const SettingsPage({super.key});

  Future<void> _adminHome(BuildContext context) async {
    await Navigator.of(context).pushNamed(AdminHomePage.route);
  }

  void aboutApp() {
    const AboutDialog(
        applicationName: "DAU Footy Tipping",
        applicationIcon: Icon(Icons.sports_rugby),
        applicationVersion: "1.0",
        applicationLegalese: "©DAU 2024",
        children: <Widget>[
          Text("Created by Toaster."),
          Text("Sponsored by The Interview Coach."),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.people),
            title: const Text('Profile'),
            onTap: () async {
              // Trigger edit functionality
              const ProfileScreen();
            },
          ),
        ),
        Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.info),
            title: const Text('About tihs app'),
            onTap: () async {
              // Trigger edit functionality
              aboutApp();
            },
          ),
        ),
        Card(
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.settings_applications),
            title: const Text('Admin'),
            onTap: () async {
              // go to admin screen
              const AlertDialog(content: AdminHomePage());
            },
          ),
        ),
      ],
    );
  }
}
