import 'dart:developer';

import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_viewmodel.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

MultiProvider adminFunctions(context) {
  return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<TippersViewModel>(
          create: (_) => TippersViewModel(),
        ),
        ChangeNotifierProvider<DAUCompsViewModel>(
          create: (_) => DAUCompsViewModel(),
        ),
      ],
      child: Card(
        child: Column(children: [
          ElevatedButton(
              child: const Text('Admin Tippers'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const TippersAdminPage(),
                  ),
                );
              }),
          ElevatedButton(
            child: const Text('Admin Teams'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TeamsListPage(),
                ),
              );
            },
          ),
          ElevatedButton(
            child: const Text('Admin DAU Comps'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChangeNotifierProvider(
                    create: (context) => DAUCompsViewModel(),
                    child: const Scaffold(
                      body: DAUCompsListPage(),
                    ),
                  ),
                ),
              );
            },
          ),
        ]),
      ));
}
