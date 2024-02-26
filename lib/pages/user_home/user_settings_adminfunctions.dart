import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:watch_it/watch_it.dart';

class AdminFunctionsWidget extends StatelessWidget with WatchItMixin {
  const AdminFunctionsWidget({super.key});

  @override
  Widget build(context) {
    String selectedTipper =
        watch(di<TippersViewModel>()).selectedTipper?.dbkey ?? '';
    log('AdminFunctionsWidget.build: selectedTipper=$selectedTipper');
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(children: [
        OutlinedButton(
            child: const Text('Admin Tippers'),
            onPressed: () {
              Navigator.of(
                context,
              ).push(
                MaterialPageRoute(
                  builder: (context) => const TippersAdminPage(),
                ),
              );
            }),
        OutlinedButton(
          child: const Text('Admin Teams'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const TeamsListPage(),
              ),
            );
          },
        ),
        OutlinedButton(
          child: const Text('Admin DAU Comps'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DAUCompsListPage(),
              ),
            );
          },
        ),
        OutlinedButton(
          child: const Text('God Mode'),
          onPressed: () {
            showGodModeDialog(context, selectedTipper);
          },
        ),
        OutlinedButton(
          child: const Text('Remote Config [External Link]'),
          onPressed: () async {
            Uri url =
                Uri.parse('https://firebase.google.com/docs/remote-config');
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            } else {
              throw 'Could not launch $url';
            }
          },
        ),
      ]),
    );
  }

  void showGodModeDialog(BuildContext context, String selectedTipper) {
    showDialog(
      context: context,
      builder: (context) {
        return GodModeDialog(selectedTipper: selectedTipper);
      },
    );
  }
}

class GodModeDialog extends StatelessWidget with WatchItMixin {
  final String selectedTipper;

  const GodModeDialog({super.key, required this.selectedTipper});

  @override
  Widget build(BuildContext context) {
    String selectedTipper =
        watch(di<TippersViewModel>()).selectedTipper?.dbkey ?? '';
    return AlertDialog(
      title: const Text('God Mode'),
      content: Column(
        children: [
          const Text(
              'If you want to view the tips of another Tipper, or tip on their behalf select them from the list below.'),
          FutureBuilder<List<Tipper>>(
            future: di<TippersViewModel>().getTippers(),
            builder:
                (BuildContext context, AsyncSnapshot<List<Tipper>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const DropdownMenuItem(child: Text('Loading...'));
              } else if (snapshot.hasError) {
                return DropdownMenuItem(
                    child: Text('Error: ${snapshot.error}'));
              } else {
                return DropdownButton<String>(
                  items: snapshot.data!.map((Tipper tipper) {
                    return DropdownMenuItem<String>(
                      value: tipper.dbkey,
                      child: Text(tipper.name),
                    );
                  }).toList(),
                  value: selectedTipper,
                  onChanged: (String? newValue) async {
                    selectedTipper = newValue!;
                    di<TippersViewModel>().selectedTipper =
                        await di<TippersViewModel>().findTipper(newValue);
                  },
                );
              }
            },
          )
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
