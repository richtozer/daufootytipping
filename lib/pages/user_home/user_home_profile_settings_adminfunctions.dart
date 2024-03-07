import 'dart:developer';

import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class AdminFunctionsWidget extends StatelessWidget with WatchItMixin {
  const AdminFunctionsWidget({super.key});

  @override
  Widget build(context) {
    String selectedTipper =
        watch(di<TippersViewModel>()).selectedTipper?.dbkey ?? '';
    log('AdminFunctionsWidget.build: selectedTipper=$selectedTipper');
    return SizedBox(
      width: 300,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Column(children: [
          const SizedBox(
            width: 300,
            child: Text(
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.normal),
                'Only admins can see these options: '),
          ),
          OutlinedButton(
            child: const Text('God Mode'),
            onPressed: () {
              showGodModeDialog(context, selectedTipper);
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
        ]),
      ),
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
      icon: const Icon(Icons.warning),
      iconColor: Colors.red,
      title: const Text('God Mode'),
      content: Column(
        children: [
          const Text(
              'If you want to view the tips of another Tipper, or tip on their behalf select them from the list below and click [View]. To revert this change later, select your name and click [View].'),
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
          child: const Text('Cancel'),
          onPressed: () {
            di<TippersViewModel>().selectedTipper =
                di<TippersViewModel>().authenticatedTipper;

            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('View'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
