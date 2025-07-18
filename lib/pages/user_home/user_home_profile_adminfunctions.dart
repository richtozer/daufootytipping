import 'dart:developer';

import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';

class AdminFunctionsWidget extends StatelessWidget with WatchItMixin {
  const AdminFunctionsWidget({super.key});

  @override
  Widget build(context) {
    String selectedTipper =
        watch(di<TippersViewModel>()).selectedTipper.dbkey ?? '';
    log('AdminFunctionsWidget.build: selectedTipper=$selectedTipper');
    // grab teamViewModel from gamesViewModel
    final teamsViewModel = watch(
      di<DAUCompsViewModel>(),
    ).gamesViewModel?.teamsViewModel;
    return SizedBox(
      width: 300,
      child: Card(
        // is dark mode use grey[800] else grey[200]
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              const SizedBox(
                width: 300,
                child: Text(
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.normal),
                  'Only admins can see these options: ',
                ),
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TippersAdminPage(),
                    ),
                  );
                },
              ),
              OutlinedButton(
                child: const Text('Admin Teams'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          TeamsListPage(teamsViewModel: teamsViewModel!),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
