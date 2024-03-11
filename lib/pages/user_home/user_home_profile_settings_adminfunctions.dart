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
}
