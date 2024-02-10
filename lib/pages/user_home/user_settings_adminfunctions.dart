import 'package:daufootytipping/pages/admin_daucomps/admin_daucomps_list.dart';
import 'package:daufootytipping/pages/admin_teams/admin_teams_list.dart';
import 'package:daufootytipping/pages/admin_tippers/admin_tippers_list.dart';
import 'package:flutter/material.dart';

Widget adminFunctions(context) {
  return Card(
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
    ]),
  );
}
